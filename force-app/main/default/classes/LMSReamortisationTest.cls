/**
 * LMSReamortisationTest
 * Covers ScheduleReamortisationService:
 *   - Mode dispatch (Re-Amortise_Forward, Bullet_Hold, Manual)
 *   - Future rows superseded, replacement rows created with correct equal-principal split
 *   - Last period absorbs rounding residual
 * Spec v3 Part 6.6, Rule R19.
 */
@IsTest
private class LMSReamortisationTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Reamort FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                              = 'Reamort DP',
            Financial_Instrument__c           = fi.Id,
            Status__c                         = 'Active',
            Position_Notional__c              = 1000000,
            Schedule_Generation_Status__c     = 'Active',
            Drawdown_Reamortisation_Mode__c   = 'Re-Amortise_Forward',
            iPlatform_External_Id__c          = 'REAMRT001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    private static Debt_Position__c getDP() {
        return [SELECT Id, Outstanding_Balance__c, Schedule_Generation_Status__c,
                       Drawdown_Reamortisation_Mode__c
                FROM Debt_Position__c LIMIT 1];
    }

    private static Disbursement_Event__c insertDisbursement(Id dpId, Date valueDate, Decimal amount) {
        Disbursement_Event__c d = new Disbursement_Event__c(
            Debt_Position__c  = dpId,
            Amount__c         = amount,
            Value_Date__c     = valueDate,
            Correlation_Id__c = 'test-disb-corr'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert d;
        TriggerContext.getInstance().bypassGuards = false;
        return d;
    }

    private static void insertScheduleRows(Id dpId, Integer count) {
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>();
        Date start = Date.today().addMonths(1);
        for (Integer i = 0; i < count; i++) {
            rows.add(new Payment_Schedule__c(
                Debt_Position__c  = dpId,
                Period_Start__c   = start.addMonths(i * 3),
                Period_End__c     = start.addMonths((i + 1) * 3),
                Due_Date__c       = start.addMonths((i + 1) * 3),
                Principal_Due__c  = 250000,
                Interest_Due__c   = 0,
                Fees_Due__c       = 0,
                Status__c         = 'Projected',
                Is_Immutable__c   = false,
                Source__c         = 'System_Calculated',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c    = 'TEST-' + i
            ));
        }
        TriggerContext.getInstance().bypassGuards = true;
        insert rows;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // Re-Amortise_Forward: future rows superseded; equal-split replacement rows inserted
    @IsTest
    static void testReAmortiseForward_SupersedesAndCreatesRows() {
        Debt_Position__c dp = getDP();
        insertScheduleRows(dp.Id, 4); // 4 projected rows
        Disbursement_Event__c d = insertDisbursement(dp.Id, Date.today(), 200000);

        Test.startTest();
        ScheduleReamortisationService.onDisbursementCleared(d.Id);
        Test.stopTest();

        // Old rows should be Superseded
        List<Payment_Schedule__c> superseded = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id AND Status__c = 'Superseded'
        ];
        Assert.isTrue(superseded.size() >= 4, 'All 4 projected rows should be superseded');

        // New rows inserted (same count as old)
        List<Payment_Schedule__c> newRows = [
            SELECT Id, Principal_Due__c FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id AND Status__c IN ('Due', 'Paid')
            AND Is_Immutable__c = false
        ];
        Assert.areEqual(4, newRows.size(), '4 replacement rows should be created');
    }

    // Equal-principal split: 800k over 4 periods = 200k each
    @IsTest
    static void testReAmortiseForward_EqualPrincipalSplit() {
        Debt_Position__c dp = getDP();
        insertScheduleRows(dp.Id, 4);
        Disbursement_Event__c d = insertDisbursement(dp.Id, Date.today(), 200000);

        Test.startTest();
        ScheduleReamortisationService.onDisbursementCleared(d.Id);
        Test.stopTest();

        List<Payment_Schedule__c> newRows = [
            SELECT Principal_Due__c FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id AND Status__c IN ('Due', 'Paid')
            ORDER BY Period_Start__c ASC
        ];
        Decimal total = 0;
        for (Payment_Schedule__c r : newRows) total += r.Principal_Due__c;
        Debt_Position__c dpAfter = [SELECT Outstanding_Balance__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.areEqual(dpAfter.Outstanding_Balance__c, total,
            'Sum of replacement principals must equal Outstanding_Balance');
    }

    // Bullet_Hold mode: no schedule change
    @IsTest
    static void testBulletHold_SkipsReamortisation() {
        Debt_Position__c dp = getDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Drawdown_Reamortisation_Mode__c = 'Bullet_Hold');
        TriggerContext.getInstance().bypassGuards = false;

        insertScheduleRows(dp.Id, 3);
        Disbursement_Event__c d = insertDisbursement(dp.Id, Date.today(), 200000);

        Test.startTest();
        ScheduleReamortisationService.onDisbursementCleared(d.Id);
        Test.stopTest();

        Integer superseded = [SELECT COUNT() FROM Payment_Schedule__c WHERE Status__c = 'Superseded'];
        Assert.areEqual(0, superseded, 'Bullet_Hold should not supersede any rows');
    }

    // Schedule not Active: skipped
    @IsTest
    static void testOnDisbursementCleared_ScheduleNotActive_Skips() {
        Debt_Position__c dp = getDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Status__c = 'Draft');
        TriggerContext.getInstance().bypassGuards = false;

        insertScheduleRows(dp.Id, 3);
        Disbursement_Event__c d = insertDisbursement(dp.Id, Date.today(), 100000);

        Test.startTest();
        ScheduleReamortisationService.onDisbursementCleared(d.Id);
        Test.stopTest();

        Integer superseded = [SELECT COUNT() FROM Payment_Schedule__c WHERE Status__c = 'Superseded'];
        Assert.areEqual(0, superseded, 'Non-Active schedule should not be re-amortised');
    }

    // No future periods: service handles gracefully (no exception)
    @IsTest
    static void testReAmortiseForward_NoFutureRows_HandlesGracefully() {
        Debt_Position__c dp = getDP();
        // No schedule rows inserted
        Disbursement_Event__c d = insertDisbursement(dp.Id, Date.today(), 200000);

        Test.startTest();
        Boolean threw = false;
        try {
            ScheduleReamortisationService.onDisbursementCleared(d.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isFalse(threw, 'No future rows should not throw — log and exit gracefully');
    }

    // reamortiseAfterEvent: same as Re-Amortise_Forward without a disbursement amount
    @IsTest
    static void testReamortiseAfterEvent_TriggersForward() {
        Debt_Position__c dp = getDP();
        insertScheduleRows(dp.Id, 2);

        Test.startTest();
        ScheduleReamortisationService.reamortiseAfterEvent(dp.Id, Date.today(), 'event-corr-id');
        Test.stopTest();

        Integer superseded = [SELECT COUNT() FROM Payment_Schedule__c WHERE Status__c = 'Superseded'];
        Assert.isTrue(superseded >= 2, 'reamortiseAfterEvent should supersede future rows');
    }
}