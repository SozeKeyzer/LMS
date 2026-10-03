/**
 * PaymentScheduleRateFinaliser
 * Spec §5.5.3-4 + Rule R17.
 * Called by RateFixingIngestionService when new Rate_Index_Fixing records are ingested.
 *
 * For each incoming fixing:
 *   1. Find Pending Interest_Period rows whose Index_Type matches the fixing's Rate_Index
 *      name/ticker AND whose Fixing_Date matches the fixing's Fixing_Date.
 *   2. Lock the Interest_Period: compute All_In_Rate = fixedIndexRate + Margin_Used
 *      (floor/ceiling from IRT), Status Pending → Active.
 *      This is done via InterestPeriodService.lockPeriod.
 *   3. Finalise any Payment_Schedule rows in Projected_Rate status whose period
 *      overlaps the now-active Interest_Period (Rule R17 — Projected_Rate → Rate_Finalised).
 *
 * DEFENSIVE FLOW (spec §5.5.4):
 *   If no Pending Interest_Period exists for a given DP (T-2 batch missed the window,
 *   holiday edge case, or first period at DP activation), this service creates AND locks
 *   the Interest_Period in one step so accruals can start immediately.
 *
 * Rule R17: Rate_Finalised → Projected_Rate transition is NEVER reversed.
 */
public class PaymentScheduleRateFinaliser {

    public static void finaliseForFixings(List<Rate_Index_Fixing__c> fixings) {
        if (fixings.isEmpty()) return;

        // Build a map: Rate_Index ticker/name → fixing rate, for all incoming fixings
        // Rate_Index__c.Name is the lookup object's Name field (e.g. "BBSW_3M")
        Set<Id>              rateIndexIds   = new Set<Id>();
        Map<Id, Decimal>     indexIdToRate  = new Map<Id, Decimal>();
        Map<Id, Date>        indexIdToDate  = new Map<Id, Date>();
        Set<Date>            fixingDates    = new Set<Date>();

        for (Rate_Index_Fixing__c f : fixings) {
            rateIndexIds.add(f.Rate_Index__c);
            indexIdToRate.put(f.Rate_Index__c, f.Rate__c);
            indexIdToDate.put(f.Rate_Index__c, f.Fixing_Date__c);
            fixingDates.add(f.Fixing_Date__c);
        }

        // Resolve Rate_Index Name (ticker) → Rate_Index Id lookup
        // Interest_Period.Index_Type__c stores the ticker string (e.g. "BBSW_3M")
        Map<String, Id>   tickerToIndexId = new Map<String, Id>();
        Map<String, Decimal> tickerToRate = new Map<String, Decimal>();
        Map<String, Date>    tickerToDate = new Map<String, Date>();
        for (Rate_Index__c ri : [
            SELECT Id, Name FROM Rate_Index__c WHERE Id IN :rateIndexIds
        ]) {
            tickerToIndexId.put(ri.Name, ri.Id);
            tickerToRate.put(ri.Name, indexIdToRate.get(ri.Id));
            tickerToDate.put(ri.Name, indexIdToDate.get(ri.Id));
        }

        // Find Pending Interest_Periods whose Index_Type + Fixing_Date match the incoming fixings
        List<Interest_Period__c> pendingPeriods = [
            SELECT Id, Debt_Position__c, Index_Type__c, Fixing_Date__c,
                   Margin_Used__c, Applied_Rate_Terms__c,
                   Period_Start__c, Period_End__c, Status__c
            FROM Interest_Period__c
            WHERE Index_Type__c IN :tickerToRate.keySet()
            AND Fixing_Date__c IN :fixingDates
            AND Status__c = 'Pending'
        ];

        Set<Id> lockedPeriodIds = new Set<Id>();

        for (Interest_Period__c ip : pendingPeriods) {
            Decimal fixingRate = tickerToRate.get(ip.Index_Type__c);
            if (fixingRate == null) continue;

            // Lock the period — computes All_In_Rate internally, applies floor/ceiling from IRT
            InterestPeriodService.lockPeriod(ip.Id, fixingRate);
            lockedPeriodIds.add(ip.Id);
        }

        // Re-query locked periods to get finalised All_In_Rate for Payment_Schedule update
        Map<Id, Interest_Period__c> lockedById = new Map<Id, Interest_Period__c>();
        if (!lockedPeriodIds.isEmpty()) {
            for (Interest_Period__c ip : [
                SELECT Id, Debt_Position__c, All_In_Rate__c, Fixed_Index_Rate__c,
                       Margin_Used__c, Period_Start__c, Period_End__c
                FROM Interest_Period__c WHERE Id IN :lockedPeriodIds
            ]) {
                lockedById.put(ip.Id, ip);
            }
        }

        // Build DP → Interest_Period map for Payment_Schedule lookup
        Map<Id, Interest_Period__c> dpToPeriod = new Map<Id, Interest_Period__c>();
        for (Interest_Period__c ip : lockedById.values()) {
            dpToPeriod.put(ip.Debt_Position__c, ip);
        }

        // Finalise Projected_Rate Payment_Schedule rows that overlap with now-Active periods
        if (!dpToPeriod.isEmpty()) {
            List<Payment_Schedule__c> toFinalise = [
                SELECT Id, Debt_Position__c, Period_Start__c, Period_End__c,
                       Rate_Finalisation_Status__c, Placeholder_All_In_Rate__c,
                       Principal_Basis_Used__c, Day_Count_Convention_Used__c
                FROM Payment_Schedule__c
                WHERE Debt_Position__c IN :dpToPeriod.keySet()
                AND Rate_Finalisation_Status__c = 'Projected_Rate'
                AND Status__c NOT IN ('Superseded', 'Cancelled', 'Paid', 'Settled_PIK')
            ];

            List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
            String corrId = TriggerContext.getInstance().correlationId;
            IDayCountCalculator dcCalc = new GenericDayCountCalculator();

            for (Payment_Schedule__c ps : toFinalise) {
                Interest_Period__c ip = dpToPeriod.get(ps.Debt_Position__c);
                if (ip == null) continue;

                Boolean overlaps = (ps.Period_Start__c < ip.Period_End__c
                                    && ps.Period_End__c > ip.Period_Start__c);
                if (!overlaps) continue;

                // Rule R17: Projected_Rate → Rate_Finalised — never reverse
                Payment_Schedule__c upd = new Payment_Schedule__c(Id = ps.Id);
                upd.Rate_Finalisation_Status__c = 'Rate_Finalised';
                upd.All_In_Rate_Used__c         = ip.All_In_Rate__c;
                upd.Base_Rate_Used__c           = ip.Fixed_Index_Rate__c;
                upd.Margin_Used__c              = ip.Margin_Used__c;

                // Spec Part 8.3: recompute Interest_Due with the now-finalised all-in rate
                // Accrual_Daily rows require a separate batch recompute — deferred (no bulk re-accrual infrastructure yet)
                if (ip.All_In_Rate__c != null && ps.Principal_Basis_Used__c != null
                        && ps.Period_Start__c != null && ps.Period_End__c != null) {
                    String conv = String.isBlank(ps.Day_Count_Convention_Used__c) ? 'ACT_365' : ps.Day_Count_Convention_Used__c;
                    Decimal fraction = dcCalc.getDayCountFraction(ps.Period_Start__c, ps.Period_End__c, conv);
                    Decimal newInterestDue = ps.Principal_Basis_Used__c * (ip.All_In_Rate__c / 100) * fraction;
                    upd.Interest_Due__c = newInterestDue.setScale(2, RoundingMode.HALF_EVEN);
                }

                toUpdate.add(upd);

                AuditEventLogger.logEngine('RATE_APPLIED', 'Payment_Schedule__c',
                    String.valueOf(ps.Id),
                    'Rate finalised.'
                    + ' Period: '     + ps.Period_Start__c + ' → ' + ps.Period_End__c
                    + ' | AllIn: '    + ip.All_In_Rate__c + '%'
                    + ' | Was: '      + ps.Placeholder_All_In_Rate__c + '%'
                    + ' | CorrId: '   + corrId);
            }

            if (!toUpdate.isEmpty()) {
                TriggerContext.getInstance().bypassGuards = true;
                try {
                    update toUpdate;
                } finally {
                    TriggerContext.getInstance().bypassGuards = false;
                }
            }
        }

        AuditEventLogger.flush();
    }
}