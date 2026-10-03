public with sharing class DebtPositionKpiController {

    @AuraEnabled(cacheable=true)
    public static KpiDTO getKpis(Id recordId) {
        KpiDTO dto = new KpiDTO();
        Date today    = Date.today();
        Date yearStart = Date.newInstance(today.year(), 1, 1);

        // ── 1. Calc mode ────────────────────────────────────────────────────
        Debt_Position__c dp = [
            SELECT Calc_Mode__c
            FROM Debt_Position__c
            WHERE Id = :recordId
        ];
        dto.calcMode = dp.Calc_Mode__c;

        // ── 2. Outstanding balance — most recent accrual day ≤ today ────────
        List<Accrual_Daily__c> latestAccrual = [
            SELECT Principal_Basis__c, Accrual_Date__c
            FROM Accrual_Daily__c
            WHERE Debt_Position__c = :recordId
              AND Accrual_Date__c <= :today
            ORDER BY Accrual_Date__c DESC
            LIMIT 1
        ];
        Decimal outstanding = latestAccrual.isEmpty()
            ? 0
            : (latestAccrual[0].Principal_Basis__c != null ? latestAccrual[0].Principal_Basis__c : 0);
        dto.outstandingFormatted = formatCurrency(outstanding);
        dto.outstandingDelta     = latestAccrual.isEmpty()
            ? ''
            : 'As of ' + formatDate(latestAccrual[0].Accrual_Date__c);

        // ── 3. Next payment due ──────────────────────────────────────────────
        List<Payment_Schedule__c> upcoming = [
            SELECT Due_Date__c, Total_Due__c, Status__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :recordId
              AND Due_Date__c >= :today
              AND Status__c IN ('Projected', 'Due', 'Partial')
            ORDER BY Due_Date__c ASC
            LIMIT 1
        ];
        if (!upcoming.isEmpty()) {
            Payment_Schedule__c ps = upcoming[0];
            dto.nextPaymentFormatted = formatCurrency(ps.Total_Due__c);
            dto.nextPaymentDate      = formatDate(ps.Due_Date__c);
            dto.daysToPayment        = ps.Due_Date__c != null ? today.daysBetween(ps.Due_Date__c) : 0;
        } else {
            dto.nextPaymentFormatted = '—';
            dto.nextPaymentDate      = 'No upcoming';
            dto.daysToPayment        = 0;
        }

        // ── 4. Accrued interest YTD ──────────────────────────────────────────
        AggregateResult[] ytd = [
            SELECT SUM(Accrued_Amount__c) total
            FROM Accrual_Daily__c
            WHERE Debt_Position__c = :recordId
              AND Accrual_Date__c >= :yearStart
              AND Accrual_Date__c <= :today
        ];
        Decimal ytdAccrual = (!ytd.isEmpty() && ytd[0].get('total') != null)
            ? (Decimal) ytd[0].get('total')
            : 0;
        dto.accruedYtdFormatted = formatCurrency(ytdAccrual);
        dto.asOf                = String.valueOf(today);

        // ── 5. Days to maturity — last non-superseded payment ───────────────
        List<Payment_Schedule__c> lastPayment = [
            SELECT Due_Date__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :recordId
              AND Status__c NOT IN ('Superseded', 'Cancelled')
            ORDER BY Due_Date__c DESC
            LIMIT 1
        ];
        if (!lastPayment.isEmpty() && lastPayment[0].Due_Date__c != null) {
            Date mat = lastPayment[0].Due_Date__c;
            Integer daysLeft = today.daysBetween(mat);
            dto.daysToMaturity      = daysLeft;
            Decimal yrs = daysLeft / 365.0;
            dto.maturityYearsRemaining = yrs.setScale(1) + ' yrs · ' + formatDate(mat);
        } else {
            dto.daysToMaturity         = 0;
            dto.maturityYearsRemaining = '';
        }

        // ── 6. Drawn / Undrawn — no commitment field in schema yet ──────────
        // Outstanding balance serves as "drawn"; utilisation cannot be computed
        // without a facility commitment field. Shown as informational only.
        dto.utilisedPct  = 0;
        dto.drawnUndrawn = formatCurrency(outstanding) + ' drawn';

        // ── 7. Current rate — active interest period ─────────────────────────
        List<Interest_Period__c> periods = [
            SELECT All_In_Rate__c, Margin_Used__c, Fixed_Index_Rate__c,
                   Period_Start__c, Period_End__c
            FROM Interest_Period__c
            WHERE Debt_Position__c = :recordId
              AND Period_Start__c <= :today
              AND Period_End__c   >= :today
            ORDER BY Period_Start__c DESC
            LIMIT 1
        ];
        if (periods.isEmpty()) {
            // Fallback: most recent period before today
            periods = [
                SELECT All_In_Rate__c, Margin_Used__c, Fixed_Index_Rate__c,
                       Period_Start__c, Period_End__c
                FROM Interest_Period__c
                WHERE Debt_Position__c = :recordId
                ORDER BY Period_Start__c DESC
                LIMIT 1
            ];
        }
        if (!periods.isEmpty()) {
            Interest_Period__c ip = periods[0];
            Decimal allIn = ip.All_In_Rate__c != null ? ip.All_In_Rate__c : 0;
            dto.currentRateFormatted = formatRate(allIn);
            List<String> parts = new List<String>();
            if (ip.Fixed_Index_Rate__c != null) {
                parts.add(formatRate(ip.Fixed_Index_Rate__c) + ' index');
            }
            if (ip.Margin_Used__c != null) {
                parts.add(formatRate(ip.Margin_Used__c) + ' margin');
            }
            dto.rateBreakdown = String.join(parts, ' + ');
        } else {
            dto.currentRateFormatted = '—';
            dto.rateBreakdown        = '';
        }

        return dto;
    }

    private static String formatCurrency(Decimal val) {
        if (val == null || val == 0) return '$0';
        return '$' + val.setScale(2).format();
    }

    private static String formatDate(Date d) {
        if (d == null) return '';
        return d.format();
    }

    // All rate fields on Interest_Period__c store actual percentages (6.25 for 6.25%)
    private static String formatRate(Decimal val) {
        if (val == null) return '0.0000%';
        return val.setScale(4) + '%';
    }

    public class KpiDTO {
        @AuraEnabled public String  outstandingFormatted;
        @AuraEnabled public String  outstandingDelta;
        @AuraEnabled public String  nextPaymentFormatted;
        @AuraEnabled public String  nextPaymentDate;
        @AuraEnabled public Integer daysToPayment;
        @AuraEnabled public String  accruedYtdFormatted;
        @AuraEnabled public String  asOf;
        @AuraEnabled public Integer daysToMaturity;
        @AuraEnabled public String  maturityYearsRemaining;
        @AuraEnabled public Integer utilisedPct;
        @AuraEnabled public String  drawnUndrawn;
        @AuraEnabled public String  currentRateFormatted;
        @AuraEnabled public String  rateBreakdown;
        @AuraEnabled public String  calcMode;
    }
}