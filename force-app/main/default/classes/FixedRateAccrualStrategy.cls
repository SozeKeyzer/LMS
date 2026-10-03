/**
 * FixedRateAccrualStrategy — ICalculationStrategy wrapper
 *
 * Preview  → computes Accrual_Daily__c rows in-memory for the active interest
 *            period using today's All_In_Rate__c and Principal_Basis. Nothing written.
 * Commit   → upserts computed rows by External_Id__c (idempotent re-runs).
 */
public with sharing class FixedRateAccrualStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages    = new List<String>();
        result.invalidatesDownstream = new List<String>{ 'Holder_Economics_Allocation' };

        List<Accrual_Daily__c> rows = buildAccrualRows(ctx.parentRecordId, false, 'FX');

        if (ctx.runMode == 'Preview') {
            result.outputRows = rows;
            result.inputsSnapshot = new Map<String, Object>{
                'mode' => 'Preview', 'projectedRows' => rows.size()
            };
        } else {
            if (!rows.isEmpty()) {
                Database.upsert(rows, Accrual_Daily__c.Fields.External_Id__c, false);
            }
            result.outputRows = rows;
            result.inputsSnapshot = new Map<String, Object>{
                'mode' => 'Commit', 'accrualRows' => rows.size()
            };
        }
        return result;
    }

    public static List<Accrual_Daily__c> buildAccrualRows(Id dpId, Boolean isPIK, String prefix) {
        List<Interest_Period__c> periods = [
            SELECT Id, All_In_Rate__c, Period_Start__c, Period_End__c
            FROM Interest_Period__c
            WHERE Debt_Position__c = :dpId
              AND Period_Start__c <= :Date.today()
            ORDER BY Period_Start__c DESC
            LIMIT 1
        ];
        if (periods.isEmpty()) return new List<Accrual_Daily__c>();
        Interest_Period__c ip = periods[0];

        Decimal principalBasis = resolvePrincipal(dpId, ip.Period_Start__c);

        List<Debt_Position__c> dps = [
            SELECT Day_Count_Convention__c FROM Debt_Position__c WHERE Id = :dpId
        ];
        String convention = (!dps.isEmpty() && String.isNotBlank(dps[0].Day_Count_Convention__c))
            ? dps[0].Day_Count_Convention__c : 'ACT_365';

        // For daily accrual, derive a fixed day-count denominator from the convention.
        // 30/360 variants treat each calendar day as 1/360; ACT/ACT ISDA uses the
        // leap-year denominator of the interest period's start year.
        Decimal daysInYear;
        if (convention == 'ACT_360' || convention == 'THIRTY_360_US' || convention == 'THIRTY_360_EU') {
            daysInYear = 360;
        } else if (convention == 'ACT_ACT_ISDA') {
            Integer yr = ip.Period_Start__c.year();
            Boolean leap = (Math.mod(yr, 4) == 0 && Math.mod(yr, 100) != 0) || Math.mod(yr, 400) == 0;
            daysInYear = leap ? 366 : 365;
        } else {
            daysInYear = 365; // ACT_365 and default
        }

        Decimal rate    = ip.All_In_Rate__c != null ? ip.All_In_Rate__c : 0;
        Decimal dcf     = (1.0 / daysInYear).setScale(8, RoundingMode.HALF_UP);
        Decimal daily   = (principalBasis * (rate / 100) * dcf).setScale(2, RoundingMode.HALF_UP);
        Date   fromDate = ip.Period_Start__c;
        Date   toDate   = ip.Period_End__c < Date.today() ? ip.Period_End__c : Date.today();

        List<Accrual_Daily__c> rows = new List<Accrual_Daily__c>();
        for (Date cur = fromDate; cur <= toDate; cur = cur.addDays(1)) {
            rows.add(new Accrual_Daily__c(
                Debt_Position__c      = dpId,
                Interest_Period__c    = ip.Id,
                Accrual_Date__c       = cur,
                Principal_Basis__c    = principalBasis,
                Rate__c               = rate,
                Day_Count_Fraction__c = dcf,
                Accrued_Amount__c     = daily,
                Is_PIK__c             = isPIK,
                Status__c             = 'Accrued',
                Source__c             = 'System_Calculated',
                External_Id__c        = String.valueOf(dpId) + '-' + prefix + '-' + cur.format()
            ));
        }
        return rows;
    }

    // Outstanding principal: last accrual day's basis, falling back to first PS principal basis
    private static Decimal resolvePrincipal(Id dpId, Date periodStart) {
        List<Accrual_Daily__c> prev = [
            SELECT Principal_Basis__c FROM Accrual_Daily__c
            WHERE Debt_Position__c = :dpId
              AND Accrual_Date__c < :periodStart
            ORDER BY Accrual_Date__c DESC LIMIT 1
        ];
        if (!prev.isEmpty() && prev[0].Principal_Basis__c != null) {
            return prev[0].Principal_Basis__c;
        }
        List<Payment_Schedule__c> ps = [
            SELECT Principal_Basis_Used__c FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c NOT IN ('Superseded', 'Cancelled')
            ORDER BY Due_Date__c ASC LIMIT 1
        ];
        return (!ps.isEmpty() && ps[0].Principal_Basis_Used__c != null)
            ? ps[0].Principal_Basis_Used__c : 0;
    }
}