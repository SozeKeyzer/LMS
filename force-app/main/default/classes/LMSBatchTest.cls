/**
 * LMSBatchTest
 * Covers: PeriodCloseBatch, OverdueDetectionBatch, InterestPeriodCreationBatch,
 *         ProjectionExpiryBatch, NotificationDispatchBatch, RateApplicationNotifyBatch,
 *         DailyAccrualScheduler, InterestPeriodCreationScheduler, RateFixingIngestionScheduler,
 *         ManualEntryService
 */
@IsTest
private class LMSBatchTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Batch FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Batch DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            Waterfall_Rule__c        = 'STANDARD',
            PIK_Allowed__c           = false,
            iPlatform_External_Id__c = 'BATCH-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Application_Status__c = 'Applied',
            Spread__c             = 8.0
        );
        insert irt;

        // Active interest period ending yesterday (ready to close)
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            Period_Start__c       = Date.today().addDays(-31),
            Period_End__c         = Date.today().addDays(-1),
            All_In_Rate__c        = 8.0,
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;

        // Accrual for the period
        Accrual_Daily__c ad = new Accrual_Daily__c(
            Debt_Position__c  = dp.Id,
            Interest_Period__c = ip.Id,
            Accrual_Date__c   = Date.today().addDays(-30),
            Accrued_Amount__c = 219.18,
            Is_PIK__c         = false,
            Status__c         = 'Accrued',
            Principal_Basis__c = 1000000,
            Rate__c           = 8.0,
            Day_Count_Fraction__c = 0.002740,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = String.valueOf(dp.Id) + '-batch-setup'
        );
        insert ad;

        // Due payment schedule (past due)
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c = dp.Id,
            Period_Start__c  = Date.today().addDays(-31),
            Period_End__c    = Date.today().addDays(-1),
            Due_Date__c      = Date.today().addDays(-1),
            Principal_Due__c = 100000,
            Interest_Due__c  = 6575,
            Fees_Due__c      = 0,
            Status__c        = 'Due',
            Source__c        = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c   = 'PS-BATCH-SETUP-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── PeriodCloseBatch ────────────────────────────────────────────────────

    @IsTest
    static void testPeriodCloseBatch_ClosesActivePeriod() {
        Test.startTest();
        Database.executeBatch(new PeriodCloseBatch(), 200);
        Test.stopTest();

        List<Interest_Period__c> closed = [
            SELECT Status__c FROM Interest_Period__c WHERE Status__c = 'Closed'
        ];
        Assert.isFalse(closed.isEmpty(), 'PeriodCloseBatch must close Active periods past their end date');
    }

    // ─── OverdueDetectionBatch ───────────────────────────────────────────────

    @IsTest
    static void testOverdueDetectionBatch_DueToOverdue() {
        Test.startTest();
        Database.executeBatch(new OverdueDetectionBatch(), 200);
        Test.stopTest();

        List<Payment_Schedule__c> overdue = [
            SELECT Status__c FROM Payment_Schedule__c WHERE Status__c = 'Overdue'
        ];
        Assert.isFalse(overdue.isEmpty(), 'OverdueDetectionBatch must transition past-due schedules to Overdue');
    }

    // ─── InterestPeriodCreationBatch ─────────────────────────────────────────

    @IsTest
    static void testInterestPeriodCreationBatch_RunsWithoutException() {
        Test.startTest();
        Boolean threw = false;
        try {
            Database.executeBatch(new InterestPeriodCreationBatch(Date.today()), 200);
        } catch (Exception e) { threw = true; }
        Test.stopTest();

        Assert.isFalse(threw, 'InterestPeriodCreationBatch must execute without exception');
    }

    @IsTest
    static void testInterestPeriodCreationBatch_Idempotent_NoDuplicate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id AND Application_Status__c = 'Applied' LIMIT 1];
        // Pre-create an interest period for today to trigger idempotency
        Interest_Period__c existingIp = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            Period_Start__c       = Date.today(),
            Period_End__c         = Date.today().addMonths(1),
            All_In_Rate__c        = 8.0,
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert existingIp;
        TriggerContext.getInstance().bypassGuards = false;

        Integer beforeCount = [SELECT COUNT() FROM Interest_Period__c WHERE Debt_Position__c = :dp.Id AND Period_Start__c = :Date.today()];

        Database.executeBatch(new InterestPeriodCreationBatch(Date.today()), 200);

        Integer afterCount = [SELECT COUNT() FROM Interest_Period__c WHERE Debt_Position__c = :dp.Id AND Period_Start__c = :Date.today()];
        Assert.areEqual(beforeCount, afterCount, 'Running batch when period already exists must not create duplicate');
    }

    // ─── ProjectionExpiryBatch ───────────────────────────────────────────────

    @IsTest
    static void testProjectionExpiryBatch_ExpiresOldGeneratedProjections() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c      = dp.Id,
            Status__c             = 'Generated',
            Projection_Type__c    = 'Amendment_Preview',
            Source__c             = 'System_Calculated',
            Engine_Version__c     = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c     = 'expire-test',
            Generated_DateTime__c = Datetime.now().addDays(-91)
        );
        insert proj;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Database.executeBatch(new ProjectionExpiryBatch(), 200);
        Test.stopTest();

        Projection__c projAfter = [SELECT Status__c FROM Projection__c WHERE Id = :proj.Id];
        Assert.areEqual('Expired', projAfter.Status__c,
            'ProjectionExpiryBatch must expire Generated projections older than 90 days');
    }

    // ─── NotificationDispatchBatch ───────────────────────────────────────────

    @IsTest
    static void testNotificationDispatchBatch_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            Database.executeBatch(new NotificationDispatchBatch(), 200);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'NotificationDispatchBatch must execute without exception');
    }

    // ─── RateApplicationNotifyBatch ──────────────────────────────────────────

    @IsTest
    static void testRateApplicationNotifyBatch_LogsApproachingResets() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c          = dp.Id,
            Application_Status__c     = 'Pending',
            Scheduled_Application_Date__c = Date.today().addDays(5)
        );
        insert irt;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean threw = false;
        try {
            Database.executeBatch(new RateApplicationNotifyBatch(), 200);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'RateApplicationNotifyBatch must not throw for approaching rate resets');
    }

    // ─── Schedulers ──────────────────────────────────────────────────────────

    @IsTest
    static void testDailyAccrualScheduler_Execute_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            DailyAccrualScheduler s = new DailyAccrualScheduler();
            s.execute(null);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'DailyAccrualScheduler.execute must not throw');
    }

    @IsTest
    static void testInterestPeriodCreationScheduler_Execute_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            InterestPeriodCreationScheduler s = new InterestPeriodCreationScheduler();
            s.execute(null);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'InterestPeriodCreationScheduler.execute must not throw');
    }

    @IsTest
    static void testRateFixingIngestionScheduler_Execute_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            RateFixingIngestionScheduler s = new RateFixingIngestionScheduler();
            s.execute(null);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'RateFixingIngestionScheduler.execute must not throw');
    }

    // ─── ManualEntryService ──────────────────────────────────────────────────

    @IsTest
    static void testManualEntryService_BlankSourceNote_ThrowsException() {
        ManualEntryService.ManualEntryRequest req = new ManualEntryService.ManualEntryRequest();
        req.objectApiName = 'Debt_Position__c';
        req.sourceNote    = '';
        req.source        = 'Manual_Entry';

        Boolean threw = false;
        try {
            ManualEntryService.createFromFlow(new List<ManualEntryService.ManualEntryRequest>{ req });
        } catch (ManualEntryService.ManualEntryException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Blank sourceNote must throw ManualEntryException');
    }

    @IsTest
    static void testManualEntryService_SystemCalculatedSource_ThrowsException() {
        ManualEntryService.ManualEntryRequest req = new ManualEntryService.ManualEntryRequest();
        req.objectApiName = 'Debt_Position__c';
        req.sourceNote    = 'System source note';
        req.source        = 'System_Calculated';

        Boolean threw = false;
        try {
            ManualEntryService.createFromFlow(new List<ManualEntryService.ManualEntryRequest>{ req });
        } catch (ManualEntryService.ManualEntryException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'System_Calculated source must not be allowed for manual entries');
    }

    @IsTest
    static void testManualEntryService_ValidEntry_LogsAuditEvent() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        ManualEntryService.ManualEntryRequest req = new ManualEntryService.ManualEntryRequest();
        req.objectApiName = 'Debt_Position__c';
        req.recordId      = dp.Id;
        req.sourceNote    = 'Manual fee adjustment approved by CFO';
        req.source        = 'Manual_Entry';

        Test.startTest();
        ManualEntryService.createFromFlow(new List<ManualEntryService.ManualEntryRequest>{ req });
        Test.stopTest();

        List<Audit_Event__c> events = [
            SELECT Event_Type__c FROM Audit_Event__c
            WHERE Event_Type__c = 'MANUAL_ENTRY_CREATED'
        ];
        Assert.isFalse(events.isEmpty(), 'Valid manual entry must create an Audit_Event with MANUAL_ENTRY_CREATED');
    }

    // ─── InterestPeriodCreationBatch — Fixed-rate path ───────────────────────

    @IsTest
    static void testInterestPeriodCreationBatch_FixedRatePath_CreatesActivePeriod() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'IPC Fixed FI');
        insert fi;

        Date targetStart = Date.today().addMonths(1).toStartOfMonth();

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'IPC Fixed DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            iPlatform_External_Id__c = 'IPCFX001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Fixed',
            Applicable_Fixed_Rate__c      = 8.0,
            Spread__c                     = 0,
            Contractual_Effective_From__c = targetStart.addDays(-30)
        );
        insert irt;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = targetStart,
            Period_End__c     = targetStart.addMonths(3),
            Due_Date__c       = targetStart.addMonths(3),
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Status__c         = 'Projected',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'IPC-FX-PS-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Database.executeBatch(new InterestPeriodCreationBatch(targetStart), 200);
        Test.stopTest();

        List<Interest_Period__c> created = [
            SELECT Id, Status__c, All_In_Rate__c
            FROM Interest_Period__c
            WHERE Debt_Position__c = :dp.Id AND Period_Start__c = :targetStart
        ];
        Assert.areEqual(1, created.size(), 'One Interest_Period must be created for Fixed-rate DP');
        Assert.areEqual('Active', created[0].Status__c, 'Fixed-rate period must have Status=Active');
        Assert.areEqual(8.0, created[0].All_In_Rate__c, 'All_In_Rate must equal the fixed rate');
    }

    // ─── InterestPeriodCreationBatch — Floating-rate path ────────────────────

    @IsTest
    static void testInterestPeriodCreationBatch_FloatingRatePath_CreatesPendingPeriod() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'IPC Float FI');
        insert fi;

        Date targetStart = Date.today().addMonths(2).toStartOfMonth();

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'IPC Float DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            iPlatform_External_Id__c = 'IPCFL001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Floating',
            Index_Type__c                = 'BBSW 3M',
            Spread__c                     = 2.5,
            Contractual_Effective_From__c = targetStart.addDays(-30)
        );
        insert irt;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = targetStart,
            Period_End__c     = targetStart.addMonths(3),
            Due_Date__c       = targetStart.addMonths(3),
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Status__c         = 'Projected',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'IPC-FL-PS-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Database.executeBatch(new InterestPeriodCreationBatch(targetStart), 200);
        Test.stopTest();

        List<Interest_Period__c> created = [
            SELECT Id, Status__c
            FROM Interest_Period__c
            WHERE Debt_Position__c = :dp.Id AND Period_Start__c = :targetStart
        ];
        Assert.areEqual(1, created.size(), 'One Interest_Period must be created for Floating-rate DP');
        Assert.areEqual('Pending', created[0].Status__c, 'Floating-rate period must have Status=Pending');
    }

    // ─── InterestPeriodCreationBatch — no matching IRT ───────────────────────

    @IsTest
    static void testInterestPeriodCreationBatch_NoMatchingIRT_SkipsDP() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'IPC No IRT FI');
        insert fi;

        Date targetStart = Date.today().addMonths(3).toStartOfMonth();

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'IPC No IRT DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'IPCNOIRT01'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        // IRT effective AFTER targetStart — query won't match
        insert new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Fixed',
            Applicable_Fixed_Rate__c      = 5.0,
            Contractual_Effective_From__c = targetStart.addDays(1)
        );
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Database.executeBatch(new InterestPeriodCreationBatch(targetStart), 200);
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Interest_Period__c WHERE Debt_Position__c = :dp.Id AND Period_Start__c = :targetStart];
        Assert.areEqual(0, cnt, 'DP with no covering IRT must be skipped — no period created');
    }
}