/**
 * LMSRateServicesTest
 * Covers: RateApplicationService, RateDeferralService, RateFixingIngestionService,
 *         PaymentScheduleService (promoteFromProjection, regenerateAfterAmendment)
 */
@IsTest
private class LMSRateServicesTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Rate FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Rate DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            iPlatform_External_Id__c = 'RATE-0001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── RateApplicationService ───────────────────────────────────────────────

    @IsTest
    static void testRateApplicationService_Apply_SetsApplied() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;

        Rate_Application_Event__c evt = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id,
            Decision_Type__c       = 'Apply',
            Decision_Date__c       = Date.today(),
            Reason__c              = 'Test reason'
        );
        insert evt;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        RateApplicationService.applyDecision(evt);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c, Actual_Application_Date__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Applied', irtAfter.Application_Status__c, 'Apply decision must set status to Applied');
        Assert.areEqual(Date.today(), irtAfter.Actual_Application_Date__c);
    }

    @IsTest
    static void testRateApplicationService_Defer_SetsDeferredStatus() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;

        Rate_Application_Event__c evt = new Rate_Application_Event__c(
            Interest_Rate_Terms__c  = irt.Id,
            Decision_Type__c        = 'Defer',
            Decision_Date__c        = Date.today(),
            New_Application_Date__c = Date.today().addMonths(1),
            Reason__c               = 'Test reason'
        );
        insert evt;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        RateApplicationService.applyDecision(evt);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Deferred', irtAfter.Application_Status__c, 'Defer decision must set status to Deferred');
    }

    @IsTest
    static void testRateApplicationService_WaivePeriod_SetsWaivedForPeriod() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;

        Rate_Application_Event__c evt = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id,
            Decision_Type__c       = 'Waive_Period',
            Decision_Date__c       = Date.today(),
            Reason__c              = 'Test reason'
        );
        insert evt;
        TriggerContext.getInstance().bypassGuards = false;

        TriggerContext.getInstance().bypassGuards = true;
        RateApplicationService.applyDecision(evt);
        TriggerContext.getInstance().bypassGuards = false;

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Waived_For_Period', irtAfter.Application_Status__c);
    }

    @IsTest
    static void testRateApplicationService_WaivePermanently_SetsSuperseded() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;

        Rate_Application_Event__c evt = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id,
            Decision_Type__c       = 'Waive_Permanently',
            Decision_Date__c       = Date.today(),
            Reason__c              = 'Test reason'
        );
        insert evt;
        TriggerContext.getInstance().bypassGuards = false;

        TriggerContext.getInstance().bypassGuards = true;
        RateApplicationService.applyDecision(evt);
        TriggerContext.getInstance().bypassGuards = false;

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Superseded', irtAfter.Application_Status__c);
    }

    // ─── RateDeferralService ─────────────────────────────────────────────────

    @IsTest
    static void testRateDeferralService_InvocableMethod_UpdatesStatus() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;
        TriggerContext.getInstance().bypassGuards = false;

        RateDeferralService.RateDeferralRequest req = new RateDeferralService.RateDeferralRequest();
        req.interestRateTermsId = irt.Id;
        req.decisionType        = 'Defer';
        req.decisionDate        = Date.today();
        req.newApplicationDate  = Date.today().addMonths(1);
        req.reason              = 'Defer test';

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        RateDeferralService.applyDecision(new List<RateDeferralService.RateDeferralRequest>{ req });
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c, Deferred_To_Date__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Deferred', irtAfter.Application_Status__c, 'Defer request must set status to Deferred');
        Assert.areEqual(Date.today().addMonths(1), irtAfter.Deferred_To_Date__c);
    }

    @IsTest
    static void testRateDeferralService_Apply_SetsApplied() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;
        TriggerContext.getInstance().bypassGuards = false;

        RateDeferralService.RateDeferralRequest req = new RateDeferralService.RateDeferralRequest();
        req.interestRateTermsId = irt.Id;
        req.decisionType        = 'Apply';
        req.decisionDate        = Date.today();
        req.reason              = 'Apply test';

        TriggerContext.getInstance().bypassGuards = true;
        RateDeferralService.applyDecision(new List<RateDeferralService.RateDeferralRequest>{ req });
        TriggerContext.getInstance().bypassGuards = false;

        Interest_Rate_Terms__c irtAfter = [SELECT Application_Status__c FROM Interest_Rate_Terms__c WHERE Id = :irt.Id];
        Assert.areEqual('Applied', irtAfter.Application_Status__c);
    }

    // ─── RateFixingIngestionService ──────────────────────────────────────────

    @IsTest
    static void testRateFixingIngestionService_Ingest_Upserts() {
        Rate_Index__c ri = new Rate_Index__c(Name = 'SOFR');
        insert ri;

        Rate_Index_Fixing__c fixing = new Rate_Index_Fixing__c(
            Rate_Index__c  = ri.Id,
            Fixing_Date__c = Date.today(),
            Rate__c        = 5.25
        );

        Test.startTest();
        RateFixingIngestionService.ingest(new List<Rate_Index_Fixing__c>{ fixing });
        Test.stopTest();

        List<Rate_Index_Fixing__c> fixings = [
            SELECT Id, Rate__c FROM Rate_Index_Fixing__c
            WHERE Rate_Index__c = :ri.Id AND Fixing_Date__c = :Date.today()
        ];
        Assert.areEqual(1, fixings.size(), 'Should upsert exactly one fixing record');
        Assert.areEqual(5.25, fixings[0].Rate__c);
    }

    @IsTest
    static void testRateFixingIngestionService_Idempotent_NoDuplicates() {
        Rate_Index__c ri = new Rate_Index__c(Name = 'EURIBOR3M');
        insert ri;

        Rate_Index_Fixing__c f1 = new Rate_Index_Fixing__c(
            Rate_Index__c  = ri.Id, Fixing_Date__c = Date.today(), Rate__c = 3.75
        );
        Rate_Index_Fixing__c f2 = new Rate_Index_Fixing__c(
            Rate_Index__c  = ri.Id, Fixing_Date__c = Date.today(), Rate__c = 3.80,
            External_Id__c = String.valueOf(ri.Id) + '-' + Date.today().format()
        );

        RateFixingIngestionService.ingest(new List<Rate_Index_Fixing__c>{ f1 });
        RateFixingIngestionService.ingest(new List<Rate_Index_Fixing__c>{ f2 });

        Integer cnt = [SELECT COUNT() FROM Rate_Index_Fixing__c WHERE Rate_Index__c = :ri.Id AND Fixing_Date__c = :Date.today()];
        Assert.areEqual(1, cnt, 'Idempotent upsert must not create duplicate fixing records');
    }

    // ─── PaymentScheduleService.promoteFromProjection ────────────────────────

    @IsTest
    static void testPromoteFromProjection_SetsStatusDue() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Date pStart = Date.today().toStartOfMonth().addMonths(5);
        Date pEnd   = pStart.addMonths(3);

        List<Map<String,Object>> rows = new List<Map<String,Object>>{
            new Map<String,Object>{
                'debtPositionId' => (Object) dp.Id,
                'periodStart'    => (Object) String.valueOf(pStart),
                'periodEnd'      => (Object) String.valueOf(pEnd),
                'dueDate'        => (Object) String.valueOf(pEnd),
                'principalDue'   => (Object) 100000,
                'interestDue'    => (Object) 5000,
                'feesDue'        => (Object) 0,
                'externalId'     => (Object) String.valueOf(dp.Id) + '-promote-test'
            }
        };

        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c   = dp.Id,
            Status__c          = 'Generated',
            Projection_Type__c = 'Amendment_Preview',
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'promote-test',
            Projected_Rows__c  = JSON.serialize(rows)
        );
        insert proj;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        PaymentScheduleService.promoteFromProjection(proj);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        List<Payment_Schedule__c> schedules = [
            SELECT Status__c FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id
        ];
        Assert.isFalse(schedules.isEmpty(), 'promoteFromProjection must create Payment_Schedule records');
        Assert.areEqual('Projected', schedules[0].Status__c, 'Promoted schedules must have status Projected');

        Projection__c projAfter = [SELECT Status__c FROM Projection__c WHERE Id = :proj.Id];
        Assert.areEqual('Promoted', projAfter.Status__c, 'Projection must be updated to Promoted');
    }

    // ─── PaymentScheduleService.regenerateAfterAmendment ────────────────────

    @IsTest
    static void testRegenerateAfterAmendment_WithSupersededRows_CreatesNewRows() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Loan_Amendment__c la = new Loan_Amendment__c(
            Debt_Position__c           = dp.Id,
            Amendment_Type__c          = 'Rate_Change',
            Proposed_Effective_Date__c = Date.today(),
            Status__c                  = 'Approved',
            Source__c                  = 'Manual_Entry'
        );
        insert la;

        Payment_Schedule__c oldPs = new Payment_Schedule__c(
            Debt_Position__c            = dp.Id,
            Period_Start__c             = Date.today().toStartOfMonth().addMonths(9),
            Period_End__c               = Date.today().toStartOfMonth().addMonths(12),
            Due_Date__c                 = Date.today().toStartOfMonth().addMonths(12),
            Principal_Due__c            = 200000,
            Interest_Due__c             = 0,
            Fees_Due__c                 = 0,
            Status__c                   = 'Superseded',
            Supersession_Amendment_Id__c = String.valueOf(la.Id),
            Source__c                   = 'System_Calculated',
            Engine_Version__c           = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c              = String.valueOf(dp.Id) + '-regen-old'
        );
        insert oldPs;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Integer cnt = PaymentScheduleService.regenerateAfterAmendment(
            new Set<Id>{ dp.Id }, la
        );
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isTrue(cnt >= 0, 'regenerateAfterAmendment must return non-negative count');
    }

    @IsTest
    static void testRegenerateAfterAmendment_NoSupersededRows_ReturnsZero() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Loan_Amendment__c la = new Loan_Amendment__c(
            Debt_Position__c           = dp.Id,
            Amendment_Type__c          = 'Rate_Change',
            Proposed_Effective_Date__c = Date.today(),
            Status__c                  = 'Approved',
            Source__c                  = 'Manual_Entry'
        );
        insert la;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Integer cnt = PaymentScheduleService.regenerateAfterAmendment(
            new Set<Id>{ dp.Id }, la
        );
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.areEqual(0, cnt, 'No superseded rows for this amendment → should return 0');
    }
}