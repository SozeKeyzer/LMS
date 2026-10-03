/**
 * ScheduleGenerationControllerTest
 * Covers ScheduleGenerationController — the Apex layer behind scheduleGeneratorWizard
 * and scheduleApproverView. Business rules themselves are covered by LMSMakerCheckerTest;
 * this class focuses on the controller's DTO shaping and exception wrapping.
 */
@IsTest
private class ScheduleGenerationControllerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();
    }

    private static Debt_Position__c buildQualifiedDP() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'SGC FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                          = 'SGC DP',
            Financial_Instrument__c       = fi.Id,
            Status__c                     = 'Draft',
            Position_Notional__c          = 2000000,
            Day_Count_Convention__c       = 'ACT_365',
            First_Payment_Date__c         = Date.today().addMonths(3),
            Accrual_Start_Date__c         = Date.today(),
            Position_Maturity_Date__c     = Date.today().addYears(5),
            Payment_Frequency__c          = 'Quarterly',
            Payment_Date_Rule__c          = 'Following Business Day',
            Rate_Type__c                  = 'Fixed',
            iPlatform_External_Id__c      = 'SGC-001'
        );
        insert dp;

        insert new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Application_Status__c = 'Applied'
        );
        insert new Amortisation_Rules__c(Debt_Position__c = dp.Id);

        return [SELECT Id FROM Debt_Position__c WHERE Id = :dp.Id];
    }

    @IsTest
    static void testGetStatus_FreshDP_ReturnsNotGeneratedAndFailures() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Unqualified FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'Unqualified DP', Financial_Instrument__c = fi.Id, Status__c = 'Draft',
            iPlatform_External_Id__c = 'SGC-002'
        );
        insert dp;

        Test.startTest();
        ScheduleGenerationController.StatusDTO dto = ScheduleGenerationController.getStatus(dp.Id);
        Test.stopTest();

        Assert.areEqual('Not_Generated', dto.scheduleGenerationStatus);
        Assert.isFalse(dto.preconditionFailures.isEmpty(), 'Unqualified DP should have precondition failures');
    }

    @IsTest
    static void testFullLifecycle_GenerateSubmitApprove() {
        Debt_Position__c dp = buildQualifiedDP();
        Id makerId = UserInfo.getUserId();

        Test.startTest();
        ScheduleGenerationController.generateDraft(dp.Id);
        ScheduleGenerationController.StatusDTO afterDraft = ScheduleGenerationController.getStatus(dp.Id);
        Assert.areEqual('Draft', afterDraft.scheduleGenerationStatus);

        List<ScheduleGenerationController.DraftRowDTO> rows = ScheduleGenerationController.getDraftRows(dp.Id);
        Assert.isFalse(rows.isEmpty(), 'Draft generation should produce rows');

        ScheduleGenerationController.submitForReview(dp.Id, 'Ready for review');
        ScheduleGenerationController.StatusDTO afterSubmit = ScheduleGenerationController.getStatus(dp.Id);
        Assert.areEqual('Pending_Review', afterSubmit.scheduleGenerationStatus);

        // Simulate a different checker — null out maker so current user (checker) != maker
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Maker__c = null);
        TriggerContext.getInstance().bypassGuards = false;

        ScheduleGenerationController.approve(dp.Id, 'Looks good');
        Test.stopTest();

        ScheduleGenerationController.StatusDTO afterApprove = ScheduleGenerationController.getStatus(dp.Id);
        Assert.areEqual('Active', afterApprove.scheduleGenerationStatus);

        List<Payment_Schedule__c> psRows = [
            SELECT Status__c, Is_Immutable__c FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id
        ];
        Assert.isFalse(psRows.isEmpty());
        for (Payment_Schedule__c ps : psRows) {
            Assert.isTrue(ps.Status__c == 'Due' || ps.Status__c == 'Paid',
                'Approved rows should be Due or Paid, got: ' + ps.Status__c);
            Assert.isTrue(ps.Is_Immutable__c, 'Approved rows should be locked');
        }
    }

    @IsTest
    static void testSubmitForReview_WrongStatus_ThrowsAuraHandledException() {
        Debt_Position__c dp = buildQualifiedDP();

        Boolean threw = false;
        try {
            ScheduleGenerationController.submitForReview(dp.Id, 'notes');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Assert.isTrue(threw, 'submitForReview before a Draft exists should throw');
    }

    @IsTest
    static void testReject_DeletesDraftRowsAndResetsStatus() {
        Debt_Position__c dp = buildQualifiedDP();
        Id makerId = UserInfo.getUserId();

        Test.startTest();
        ScheduleGenerationController.generateDraft(dp.Id);
        ScheduleGenerationController.submitForReview(dp.Id, 'notes');

        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Maker__c = null);
        TriggerContext.getInstance().bypassGuards = false;

        ScheduleGenerationController.reject(dp.Id, 'Missing collateral detail');
        Test.stopTest();

        ScheduleGenerationController.StatusDTO afterReject = ScheduleGenerationController.getStatus(dp.Id);
        Assert.areEqual('Not_Generated', afterReject.scheduleGenerationStatus);
        Assert.areEqual('Missing collateral detail', afterReject.lastRejectReason);

        Integer remaining = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id AND Status__c = 'Projected'];
        Assert.areEqual(0, remaining);
    }
}
