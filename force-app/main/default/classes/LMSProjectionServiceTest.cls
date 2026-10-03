/**
 * LMSProjectionServiceTest
 * Covers: ProjectionService (generateForAmendment, discard), ProjectionHandler
 */
@IsTest
private class LMSProjectionServiceTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Proj FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Proj DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'PROJ-0001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── ProjectionService.generateForAmendment ───────────────────────────────

    @IsTest
    static void testGenerateForAmendment_CreatesProjectionRecord() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Loan_Amendment__c la = new Loan_Amendment__c(
            Debt_Position__c  = dp.Id,
            Amendment_Type__c          = 'Rate_Change',
            Proposed_Effective_Date__c = Date.today(),
            Status__c                  = 'Approved',
            Source__c         = 'Manual_Entry'
        );
        insert la;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = ProjectionService.generateForAmendment(
            dp.Id, la.Id, new List<Object>()
        );
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isNotNull(proj.Id, 'generateForAmendment must return a persisted Projection__c record');
        Assert.areEqual('Generated', proj.Status__c, 'New projection must have Status=Generated');
        Assert.areEqual('Amendment_Preview', proj.Projection_Type__c);
        Assert.areEqual(dp.Id, proj.Debt_Position__c);
    }

    @IsTest
    static void testGenerateForAmendment_WithNullAmendmentId_StillCreates() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = ProjectionService.generateForAmendment(
            dp.Id, null, new List<Object>()
        );
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isNotNull(proj.Id, 'generateForAmendment with null amendmentId must still create record');
        Assert.areEqual('Generated', proj.Status__c);
    }

    @IsTest
    static void testGenerateForAmendment_WithProjectedRows_SetsJson() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        List<Object> rows = new List<Object>{
            new Map<String,Object>{ 'period' => 1, 'amount' => 10000 }
        };

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = ProjectionService.generateForAmendment(dp.Id, null, rows);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Projection__c projQueried = [SELECT Projected_Rows__c FROM Projection__c WHERE Id = :proj.Id];
        Assert.isNotNull(projQueried.Projected_Rows__c, 'Projected_Rows__c must be set from the rows list');
    }

    // ─── ProjectionService.discard ────────────────────────────────────────────

    @IsTest
    static void testDiscard_SetsStatusDiscarded() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c   = dp.Id,
            Status__c          = 'Generated',
            Projection_Type__c = 'Amendment_Preview',
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'discard-test'
        );
        insert proj;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        ProjectionService.discard(proj.Id);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Projection__c projAfter = [SELECT Status__c FROM Projection__c WHERE Id = :proj.Id];
        Assert.areEqual('Discarded', projAfter.Status__c, 'discard() must set Status to Discarded');
    }

    @IsTest
    static void testDiscard_AlreadyDiscarded_NoOp() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c   = dp.Id,
            Status__c          = 'Discarded',
            Projection_Type__c = 'Amendment_Preview',
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'already-discarded'
        );
        insert proj;
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        try {
            TriggerContext.getInstance().bypassGuards = true;
            ProjectionService.discard(proj.Id);
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }
        Assert.isFalse(threw, 'Discarding an already-Discarded projection must not throw');
    }

    // ─── ProjectionHandler ────────────────────────────────────────────────────

    @IsTest
    static void testProjectionHandler_Insert_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Boolean threw = false;
        TriggerContext.getInstance().bypassGuards = true;
        try {
            Projection__c proj = new Projection__c(
                Debt_Position__c   = dp.Id,
                Status__c          = 'Generated',
                Projection_Type__c = 'Amendment_Preview',
                Source__c          = 'System_Calculated',
                Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
                Correlation_Id__c  = 'handler-insert-test'
            );
            insert proj;
        } catch (Exception e) { threw = true; }
        TriggerContext.getInstance().bypassGuards = false;

        Assert.isFalse(threw, 'ProjectionHandler afterInsert must not throw');
    }

    @IsTest
    static void testProjectionHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c   = dp.Id,
            Status__c          = 'Generated',
            Projection_Type__c = 'Amendment_Preview',
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'handler-update-test'
        );
        insert proj;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Projection__c(Id = proj.Id, Status__c = 'Discarded');
        } catch (Exception e) { threw = true; }
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isFalse(threw, 'ProjectionHandler afterUpdate must not throw on status change');
    }
}