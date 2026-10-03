/**
 * DailyAccrualBatch — Batchable, Stateful
 * Nightly: iterates active Debt_Positions, posts Accrual_Daily records for today.
 * Handles period close events when Period_End is reached.
 * Idempotent — DailyAccrualPoster uses External_Id upsert.
 */
public class DailyAccrualBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Date accrualDate;
    private Integer processed = 0;
    private Integer errors = 0;

    public DailyAccrualBatch() { this.accrualDate = Date.today(); }
    public DailyAccrualBatch(Date d) { this.accrualDate = d; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Outstanding_Balance__c, Waterfall_Rule__c,
                   PIK_Allowed__c, PIK_Default_Mode__c, Day_Count_Convention__c
            FROM Debt_Position__c
            WHERE Status__c = 'Active'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TriggerContext.getInstance().refreshCorrelationId();

        Set<Id> dpIds = new Map<Id,SObject>(scope).keySet();
        Map<Id,Interest_Period__c> activePeriods = new Map<Id,Interest_Period__c>();
        for (Interest_Period__c ip : [
            SELECT Id, Debt_Position__c, All_In_Rate__c, Period_Start__c, Period_End__c
            FROM Interest_Period__c
            WHERE Debt_Position__c IN :dpIds
            AND Status__c = 'Active'
            AND Period_Start__c <= :accrualDate
            AND Period_End__c > :accrualDate
        ]) {
            activePeriods.put(ip.Debt_Position__c, ip);
        }

        // Resolve locked Elections for all active periods.
        // Keyed by Debt_Position__c — one locked Election per DP per period.
        Map<Id,Election__c> lockedElections = new Map<Id,Election__c>();
        Set<Date> periodStarts = new Set<Date>();
        for (Interest_Period__c ip : activePeriods.values()) periodStarts.add(ip.Period_Start__c);
        if (!periodStarts.isEmpty()) {
            for (Election__c el : [
                SELECT Id, Debt_Position__c, Election_Type__c, Cash_Amount__c, PIK_Amount__c
                FROM Election__c
                WHERE Debt_Position__c IN :dpIds
                  AND Period_Start__c IN :periodStarts
                  AND Is_Immutable__c = true
            ]) {
                lockedElections.put(el.Debt_Position__c, el);
            }
        }

        List<Accrual_Daily__c> toUpsert = new List<Accrual_Daily__c>();

        // PREVIEW mode: engine computes but does not DML — batch handles single bulk upsert
        CalculationEngine engine = new CalculationEngine(CalculationEngineBase.Mode.PREVIEW);
        // Single calculator instance — GenericDayCountCalculator caches MDT internally
        IDayCountCalculator dayCountCalc = CalculationEngineFactory.getDayCountCalculator();

        for (SObject sobj : scope) {
            Debt_Position__c dp = (Debt_Position__c) sobj;
            Interest_Period__c ip = activePeriods.get(dp.Id);
            if (ip == null) continue;

            // Convention code must match DayCount_Convention__mdt.Convention_Code__c
            String convention = String.isNotBlank(dp.Day_Count_Convention__c)
                ? dp.Day_Count_Convention__c : 'ACT_365';
            Decimal dayCountFrac = dayCountCalc.getDayCountFraction(
                accrualDate, accrualDate.addDays(1), convention);

            // Determine PIK treatment from locked Election (if present) or DP default
            Election__c election    = lockedElections.get(dp.Id);
            String electionType     = election != null ? election.Election_Type__c : null;
            Boolean isAutoFullPIK   = dp.PIK_Allowed__c && dp.PIK_Default_Mode__c == 'Auto_PIK'
                                          && election == null;

            CalcContext ctx = new CalcContext.Builder()
                .setDebtPositionId(dp.Id)
                .setPrincipal(dp.Outstanding_Balance__c ?? 0)
                .setInterestRate(ip.All_In_Rate__c ?? 0)
                .setPeriodStartDate(ip.Period_Start__c)
                .setPeriodEndDate(ip.Period_End__c)
                .setCalculationDate(accrualDate)
                .setDayCountConvention(convention)
                .setCorrelationId(TriggerContext.getInstance().correlationId)
                .setExtras(new Map<String,Object>{
                    'interestPeriodId'  => String.valueOf(ip.Id),
                    // Full PIK: Auto_PIK default OR locked full-PIK election
                    'isPIK'             => isAutoFullPIK || electionType == 'PIK',
                    'dayCountFraction'  => dayCountFrac,
                    // Split election data — used by DailyAccrualPoster to create two rows
                    'electionType'      => electionType,
                    'electionCashAmt'   => election != null ? election.Cash_Amount__c : null,
                    'electionPIKAmt'    => election != null ? election.PIK_Amount__c  : null
                })
                .build();

            EngineResult result = engine.postDailyAccrual(accrualDate, ctx);
            if (result.success) {
                toUpsert.addAll((List<Accrual_Daily__c>)(Object)result.recordsToInsert);
                processed++;
            } else {
                errors++;
                AuditEventLogger.logEngine('PERIOD_ERROR', 'Debt_Position__c',
                    String.valueOf(dp.Id), 'Accrual compute failed for ' + accrualDate);
            }

        }

        Schema.SObjectField extId = Accrual_Daily__c.Fields.External_Id__c;
        if (!toUpsert.isEmpty()) {
            List<Database.UpsertResult> upsertResults = Database.upsert(toUpsert, extId, false);
            for (Database.UpsertResult ur : upsertResults) {
                if (!ur.isSuccess()) {
                    errors++;
                    AuditEventLogger.logEngine('UPSERT_FAILURE', 'Accrual_Daily__c', null,
                        'Accrual upsert failed: ' + JSON.serialize(ur.getErrors()));
                }
            }
        }
        AuditEventLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        AuditEventLogger.logEngine('ACCRUAL_POSTED','DailyAccrualBatch',null,
            'Daily accrual batch complete. Date: ' + accrualDate + '. Processed: ' + processed + '. Errors: ' + errors);
        AuditEventLogger.flush();
    }
}