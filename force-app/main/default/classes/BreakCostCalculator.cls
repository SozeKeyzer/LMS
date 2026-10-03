/**
 * BreakCostCalculator
 * Computes break cost for Prepayment_Event records.
 * Reads Break_Cost_Formula__mdt by Basis_Code__c. Strategy pattern.
 * Each basis has its own calculation approach per spec section 6.7.2.
 */
public class BreakCostCalculator {

    private static Map<String,Break_Cost_Formula__mdt> formulaCache;

    private static Map<String,Break_Cost_Formula__mdt> getFormulas() {
        if (formulaCache == null) {
            formulaCache = new Map<String,Break_Cost_Formula__mdt>();
            for (Break_Cost_Formula__mdt f : [
                SELECT Basis_Code__c, Formula_Description__c, Formula_Expression__c, Requires_Approval__c
                FROM Break_Cost_Formula__mdt WHERE Is_Active__c = true
            ]) {
                formulaCache.put(f.Basis_Code__c, f);
            }
        }
        return formulaCache;
    }

    /**
     * Compute break cost for a prepayment event.
     * @param event  The Prepayment_Event__c record with Break_Cost_Basis__c populated
     * @param extras Additional inputs: remainingTenorYears, spreadBps, slidingScalePct, nonCallFeeAmt
     */
    public static Decimal compute(Prepayment_Event__c prepEvent, Map<String,Object> extras) {
        if (String.isBlank(prepEvent.Break_Cost_Basis__c)) return 0;

        String basis = prepEvent.Break_Cost_Basis__c;
        Decimal principal = prepEvent.Prepaid_Principal__c != null ? prepEvent.Prepaid_Principal__c : 0;

        switch on basis {
            when 'Par' {
                return 0;
            }
            when 'Sliding_Scale' {
                Decimal pct = (Decimal)(extras.get('slidingScalePct') != null ? extras.get('slidingScalePct') : 0);
                return (principal * pct / 100).setScale(2, RoundingMode.HALF_EVEN);
            }
            when 'Non_Call_Period_Breach' {
                Decimal fee = (Decimal)(extras.get('nonCallFeeAmount') != null ? extras.get('nonCallFeeAmount') : 0);
                return fee.setScale(2, RoundingMode.HALF_EVEN);
            }
            when 'Make_Whole_Treasury_Plus' {
                // NOTE: Simplified approximation — P × spread × T rather than full DCF PV.
                // True make-whole = PV(remaining cashflows at Treasury+spread) − par.
                // Spec §6.7.2 calls for full DCF; upgrade when treasury rate feed is available.
                Decimal spreadBps = (Decimal)(extras.get('spreadBps') != null ? extras.get('spreadBps') : 0);
                Decimal tenorYears = (Decimal)(extras.get('remainingTenorYears') != null ? extras.get('remainingTenorYears') : 0);
                return (principal * (spreadBps / 10000) * tenorYears).setScale(2, RoundingMode.HALF_EVEN);
            }
            when else {
                // Other: requires manual calculation — return 0 as placeholder
                return 0;
            }
        }
    }

    /**
     * Invocable from Flow. Accepts a request wrapper so Flows can supply the full
     * set of calculation inputs rather than relying on hardcoded defaults.
     * Falls back to querying IRT for spreadBps and last PS for remainingTenorYears
     * when those inputs are omitted.
     */
    @InvocableMethod(label='Calculate Break Cost' category='LMS')
    public static List<Decimal> calculateFromFlow(List<BreakCostRequest> requests) {
        List<Decimal> results = new List<Decimal>();

        for (BreakCostRequest req : requests) {
            Prepayment_Event__c pe = [
                SELECT Id, Prepaid_Principal__c, Break_Cost_Basis__c, Debt_Position__c, Prepayment_Date__c
                FROM Prepayment_Event__c WHERE Id = :req.prepaymentEventId
            ];

            Map<String,Object> extras = new Map<String,Object>();

            // Use caller-supplied values where present; derive from org data otherwise
            extras.put('slidingScalePct',  req.slidingScalePct  != null ? req.slidingScalePct  : 0);
            extras.put('nonCallFeeAmount', req.nonCallFeeAmount  != null ? req.nonCallFeeAmount  : 0);
            extras.put('spreadBps',        req.spreadBps         != null ? req.spreadBps         : resolveSpreadBps(pe.Debt_Position__c));
            extras.put('remainingTenorYears',
                req.remainingTenorYears != null ? req.remainingTenorYears : resolveRemainingTenor(pe.Debt_Position__c, pe.Prepayment_Date__c));

            Decimal cost = compute(pe, extras);
            update new Prepayment_Event__c(Id = pe.Id, Break_Cost__c = cost);
            results.add(cost);
        }
        return results;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /** Returns the spread in basis points from the most recently applied IRT for the DP. */
    private static Decimal resolveSpreadBps(Id dpId) {
        List<Interest_Rate_Terms__c> irts = [
            SELECT Spread__c FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId AND Application_Status__c = 'Applied'
            ORDER BY Actual_Application_Date__c DESC NULLS LAST LIMIT 1
        ];
        if (!irts.isEmpty() && irts[0].Spread__c != null) {
            return irts[0].Spread__c * 100; // Spread is stored as %, convert to bps
        }
        return 0;
    }

    /** Returns remaining tenor in years from prepayment date to the last scheduled PS due date. */
    private static Decimal resolveRemainingTenor(Id dpId, Date prepaymentDate) {
        List<Payment_Schedule__c> lastPs = [
            SELECT Due_Date__c FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId AND Status__c NOT IN ('Superseded','Cancelled','Settled')
            ORDER BY Due_Date__c DESC LIMIT 1
        ];
        if (!lastPs.isEmpty() && prepaymentDate != null) {
            Integer daysRemaining = prepaymentDate.daysBetween(lastPs[0].Due_Date__c);
            return (daysRemaining / 365.0).setScale(4, RoundingMode.HALF_UP);
        }
        return 0;
    }

    public class BreakCostRequest {
        @InvocableVariable(required=true  label='Prepayment Event ID')     public Id      prepaymentEventId;
        @InvocableVariable(required=false label='Sliding Scale Pct (%)')   public Decimal slidingScalePct;
        @InvocableVariable(required=false label='Non-Call Fee Amount')      public Decimal nonCallFeeAmount;
        @InvocableVariable(required=false label='Treasury Spread (bps)')   public Decimal spreadBps;
        @InvocableVariable(required=false label='Remaining Tenor (years)') public Decimal remainingTenorYears;
    }

    @TestVisible
    public static void clearCache() { formulaCache = null; }
}