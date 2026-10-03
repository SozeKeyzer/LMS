/**
 * MakeWholeCalculator
 * Forward-looking PV-based prepayment compensation per Spec v3 Part 9.5 and Rule R21.
 *
 * Formula: Make_Whole_Amount = PV(remaining cashflows at discount_rate) − prepayment_amount.
 * If result <= 0: no make-whole due (lender can redeploy at >= contractual rate).
 *
 * PV methods:
 *   Standard / Treasury_Plus — discrete: PV = CF / (1 + r)^t
 *   Yield_Maintenance — continuous: PV = CF × e^(−r × t)
 *
 * Reference rate source (AGB_3Y / AGB_5Y) is read from Rate_Index_Fixing__c.
 * Caller must run in Preview mode first; ops/credit reviews before committing.
 */
public class MakeWholeCalculator {

    public class MakeWholeResult {
        public Decimal makeWholeAmount   { get; private set; }
        public Decimal discountRate      { get; private set; }
        public Decimal pvOfCashflows     { get; private set; }
        public Decimal referenceRate     { get; private set; }
        public String  formulaName       { get; private set; }

        public MakeWholeResult(Decimal mwa, Decimal dr, Decimal pv, Decimal rr, String fn) {
            this.makeWholeAmount = mwa;
            this.discountRate    = dr;
            this.pvOfCashflows   = pv;
            this.referenceRate   = rr;
            this.formulaName     = fn;
        }
    }

    /**
     * Compute make-whole for a prepayment against a debt position.
     *
     * @param dpId             Debt_Position__c Id
     * @param prepaymentDate   Date of prepayment (used as PV discount anchor)
     * @param prepaymentAmount AUD amount being prepaid (for partial prepayment pro-ration)
     * @return MakeWholeResult, or null if no Make_Whole_Formula configured on the DP
     */
    public static MakeWholeResult compute(Id dpId, Date prepaymentDate, Decimal prepaymentAmount) {
        Debt_Position__c dp = [
            SELECT Id, Make_Whole_Formula__c, Outstanding_Balance__c, Position_Notional__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];
        if (String.isBlank(dp.Make_Whole_Formula__c)) return null;

        // Load formula definition from CMT
        List<Make_Whole_Formula__mdt> formulas = [
            SELECT DeveloperName, MasterLabel, Reference_Rate_Source__c, Make_Whole_Spread__c,
                   PV_Method__c, Effective_Date_Logic__c, Is_Active__c
            FROM Make_Whole_Formula__mdt
            WHERE DeveloperName = :dp.Make_Whole_Formula__c
              AND Is_Active__c = true
            LIMIT 1
        ];
        if (formulas.isEmpty()) {
            throw new MakeWholeException('Make_Whole_Formula__mdt record not found or inactive: '
                + dp.Make_Whole_Formula__c);
        }
        Make_Whole_Formula__mdt formula = formulas[0];

        // Resolve effective date for reference rate lookup
        Date effectiveDate = resolveEffectiveDate(prepaymentDate, formula.Effective_Date_Logic__c);

        // Get reference rate
        Decimal referenceRate = getReferenceRate(formula.Reference_Rate_Source__c, effectiveDate);
        Decimal discountRate  = referenceRate + (formula.Make_Whole_Spread__c != null ? formula.Make_Whole_Spread__c : 0);

        // Remaining schedule rows from prepayment date forward
        List<Payment_Schedule__c> remainingRows = [
            SELECT Id, Period_Start__c, Period_End__c, Due_Date__c, Principal_Due__c, Interest_Due__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Period_Start__c >= :prepaymentDate
              AND Status__c IN ('Due', 'Projected', 'Overdue')
            ORDER BY Period_Start__c ASC
        ];

        // Pro-ration factor for partial prepayments
        Decimal outstanding = dp.Outstanding_Balance__c != null ? dp.Outstanding_Balance__c : 0;
        Decimal proRata = (outstanding > 0 && prepaymentAmount < outstanding)
            ? (prepaymentAmount / outstanding) : 1.0;

        // PV sum
        Decimal pvSum = 0;
        String pvMethod = formula.PV_Method__c != null ? formula.PV_Method__c : 'Standard';
        for (Payment_Schedule__c ps : remainingRows) {
            Decimal yearsToPayment = prepaymentDate.daysBetween(ps.Due_Date__c) / 365.0;
            if (yearsToPayment <= 0) continue;
            Decimal cashflow = ((ps.Principal_Due__c != null ? ps.Principal_Due__c : 0)
                              + (ps.Interest_Due__c  != null ? ps.Interest_Due__c  : 0)) * proRata;
            Decimal pv;
            if (pvMethod == 'Yield_Maintenance') {
                pv = cashflow * (Decimal) Math.exp(-1.0 * (Double)(discountRate * yearsToPayment));
            } else {
                // Standard and Treasury_Plus both use discrete discounting
                Double base = 1.0 + (Double) discountRate;
                Double exp  = (Double) yearsToPayment;
                pv = cashflow / (Decimal) Math.pow(base, exp);
            }
            pvSum += pv;
        }

        // Make-whole = PV of remaining − amount being prepaid
        Decimal makeWholeAmount = (pvSum - prepaymentAmount).setScale(2, RoundingMode.HALF_EVEN);
        if (makeWholeAmount < 0) makeWholeAmount = 0;

        return new MakeWholeResult(makeWholeAmount, discountRate, pvSum, referenceRate,
            formula.MasterLabel);
    }

    private static Date resolveEffectiveDate(Date prepaymentDate, String logic) {
        // Prepayment_Date is default; Notice_Date / Settlement_Date require additional context
        // not available here — handled by the caller passing the appropriate date
        return prepaymentDate;
    }

    private static Decimal getReferenceRate(String source, Date asOfDate) {
        // AGB_3Y / AGB_5Y are stored as Rate_Index_Fixing records linked via Rate_Index__c.Name
        List<Rate_Index_Fixing__c> fixings = [
            SELECT Rate__c
            FROM Rate_Index_Fixing__c
            WHERE Rate_Index__r.Name = :source
              AND Fixing_Date__c <= :asOfDate
            ORDER BY Fixing_Date__c DESC
            LIMIT 1
        ];
        if (!fixings.isEmpty() && fixings[0].Rate__c != null) return fixings[0].Rate__c;
        // Fallback: AGB proxy — spec says reference rate lookup may return null if no fixing exists
        throw new MakeWholeException('No rate fixing found for reference source: ' + source
            + ' as of ' + asOfDate + '. Ingest the AGB rate before computing make-whole.');
    }

    public class MakeWholeException extends Exception {}
}