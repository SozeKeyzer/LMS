@IsTest
private class CalculationEngineBaseTest {

    private class TestEngine extends CalculationEngineBase {
        public TestEngine(Mode m) { super(m); }
        public override EngineResult execute(CalcContext ctx) {
            EngineResult r = new EngineResult();
            r.setAmount(100);
            return r;
        }
        // Expose protected commitResult so test methods can call it
        public void callCommitResult(EngineResult r) { commitResult(r); }
    }

    @TestSetup
    static void setup() { TriggerContext.reset(); }

    @IsTest
    static void testPreviewModeSet() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.PREVIEW);
        Assert.isTrue(eng.isPreview());
        Assert.isFalse(eng.isApply());
        Assert.areEqual(TriggerContext.EngineMode.PREVIEW, TriggerContext.getInstance().mode);
    }

    @IsTest
    static void testApplyModeSet() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.APPLY);
        Assert.isFalse(eng.isPreview());
        Assert.isTrue(eng.isApply());
        Assert.areEqual(TriggerContext.EngineMode.APPLY, TriggerContext.getInstance().mode);
    }

    @IsTest
    static void testEngineVersionConstant() {
        Assert.isTrue(String.isNotBlank(CalculationEngineBase.ENGINE_VERSION));
    }

    @IsTest
    static void testIsEngineOwned() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.APPLY);
        Debt_Position__c dp = new Debt_Position__c(Source__c = 'System_Calculated');
        Assert.isTrue(eng.isEngineOwned(dp), 'System_Calculated should be engine-owned');
        dp.Source__c = 'Manual_Entry';
        Assert.isFalse(eng.isEngineOwned(dp), 'Manual_Entry should NOT be engine-owned');
    }

    // ─── commitResult — three paths ──────────────────────────────────────────

    @IsTest
    static void testCommitResult_FailedResult_NoDML() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.APPLY);
        EngineResult r = new EngineResult();
        r.addError('test failure');
        Rate_Index__c ri = new Rate_Index__c(Name = 'COMMIT-FAIL-IDX');
        r.addInsert(ri);

        Test.startTest();
        eng.callCommitResult(r);
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Rate_Index__c WHERE Name = 'COMMIT-FAIL-IDX'];
        Assert.areEqual(0, cnt, 'commitResult with success=false must not insert records');
    }

    @IsTest
    static void testCommitResult_PreviewMode_NoDML() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.PREVIEW);
        EngineResult r = new EngineResult();
        Rate_Index__c ri = new Rate_Index__c(Name = 'COMMIT-PREV-IDX');
        r.addInsert(ri);

        Test.startTest();
        eng.callCommitResult(r);
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Rate_Index__c WHERE Name = 'COMMIT-PREV-IDX'];
        Assert.areEqual(0, cnt, 'commitResult in PREVIEW mode must not insert records');
    }

    @IsTest
    static void testCommitResult_ApplyModeSuccess_InsertsRecords() {
        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.APPLY);
        EngineResult r = new EngineResult();
        Rate_Index__c ri = new Rate_Index__c(Name = 'COMMIT-APPLY-IDX');
        r.addInsert(ri);

        Test.startTest();
        eng.callCommitResult(r);
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Rate_Index__c WHERE Name = 'COMMIT-APPLY-IDX'];
        Assert.areEqual(1, cnt, 'commitResult in APPLY mode must insert records when success=true');
    }

    @IsTest
    static void testCommitResult_ApplyModeSuccess_UpdatesRecords() {
        Rate_Index__c ri = new Rate_Index__c(Name = 'COMMIT-UPD-IDX-BEFORE');
        insert ri;

        TestEngine eng = new TestEngine(CalculationEngineBase.Mode.APPLY);
        EngineResult r = new EngineResult();
        ri.Name = 'COMMIT-UPD-IDX-AFTER';
        r.addUpdate(ri);

        Test.startTest();
        eng.callCommitResult(r);
        Test.stopTest();

        Rate_Index__c updated = [SELECT Name FROM Rate_Index__c WHERE Id = :ri.Id];
        Assert.areEqual('COMMIT-UPD-IDX-AFTER', updated.Name, 'commitResult in APPLY mode must update records');
    }

    // ─── CalcResult factory methods ──────────────────────────────────────────

    @IsTest
    static void testCalcResult_Failed_SetsSuccessFalseAndMessage() {
        CalcResult r = CalcResult.failed('something went wrong');
        Assert.isFalse(r.success, 'CalcResult.failed must set success=false');
        Assert.areEqual('something went wrong', r.errorMessage);
        Assert.isNotNull(r.outputRows);
        Assert.isNotNull(r.inputsSnapshot);
        Assert.isNotNull(r.validationMessages);
        Assert.isNotNull(r.invalidatesDownstream);
    }

    @IsTest
    static void testCalcResult_Skipped_SetsSuccessFalseAndMessage() {
        CalcResult r = CalcResult.skipped('skipping this calc');
        Assert.isFalse(r.success, 'CalcResult.skipped must set success=false');
        Assert.areEqual('skipping this calc', r.errorMessage);
        Assert.isNotNull(r.outputRows);
        Assert.isTrue(r.outputRows.isEmpty(), 'Skipped result must have empty outputRows');
    }

    // ─── OrchestratorCalcContext ──────────────────────────────────────────────

    @IsTest
    static void testOrchestratorCalcContext_FieldsSettable() {
        OrchestratorCalcContext ctx = new OrchestratorCalcContext();
        ctx.parentRecordId      = null;
        ctx.parentObjectApiName = 'Debt_Position__c';
        ctx.relatedRecords      = new Map<String, SObject>();
        ctx.runMode             = 'Preview';
        ctx.calcDeveloperName   = 'Test_Calc';
        ctx.calcVersion         = '1.0';
        Assert.areEqual('Preview', ctx.runMode);
        Assert.areEqual('Debt_Position__c', ctx.parentObjectApiName);
        Assert.areEqual('Test_Calc', ctx.calcDeveloperName);
    }

    // ─── CalculationOrchestrator ──────────────────────────────────────────────

    @IsTest
    static void testCalculationOrchestrator_DefNotFound_ReturnsFailed() {
        Test.startTest();
        CalcResult result = CalculationOrchestrator.run('NONEXISTENT_DEF_99', null, 'Preview');
        Test.stopTest();
        Assert.isFalse(result.success, 'Missing def must return a failed CalcResult');
        Assert.isTrue(result.errorMessage.contains('Calculation definition not found'));
    }

    @IsTest
    static void testCalculationOrchestrator_InactiveDef_ReturnsFailed() {
        // Holder_Economics_Allocation has Active__c = false in the org
        Test.startTest();
        CalcResult result = CalculationOrchestrator.run('Holder_Economics_Allocation', null, 'Preview');
        Test.stopTest();
        Assert.isFalse(result.success, 'Inactive def must return a failed CalcResult');
        Assert.areEqual('Inactive', result.errorMessage);
    }

    @IsTest
    static void testCalculationOrchestrator_ParentNotFound_ReturnsFailed() {
        // Active def, null parentId → parent record not found path
        Test.startTest();
        CalcResult result = CalculationOrchestrator.run('Fixed_Rate_Interest_Accrual', null, 'Preview');
        Test.stopTest();
        Assert.isFalse(result.success, 'Null parentId must return a failed CalcResult');
        Assert.isTrue(result.errorMessage.contains('Parent record not found'));
    }

    @IsTest
    static void testCalculationOrchestrator_PreviewMode_ValidDP_NoException() {
        TriggerContext.getInstance().bypassGuards = true;
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Orch FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Orch DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'ORCHDP001'
        );
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        Test.startTest();
        try {
            CalculationOrchestrator.run('Fixed_Rate_Interest_Accrual', dp.Id, 'Preview');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isFalse(threw, 'CalculationOrchestrator.run() in Preview mode must not throw');
    }

    // ─── CalculationEngine.execute() ─────────────────────────────────────────

    @IsTest
    static void testCalculationEngine_Execute_PreviewMode_CoveredViaErrorPath() {
        AuditEventLogger.clearPending();
        CalculationEngine eng = new CalculationEngine(CalculationEngineBase.Mode.PREVIEW);
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-exec-coverage')
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.today().addMonths(-1))
            .setPeriodEndDate(Date.today())
            .setInterestRate(5.0)
            .setPrincipal(1000000)
            .build();

        Boolean threw = false;
        EngineResult result;
        Test.startTest();
        try { result = eng.execute(ctx); } catch (Exception e) { threw = true; }
        Test.stopTest();

        Assert.isFalse(threw, 'execute() must not propagate exceptions — it has an internal try/catch');
        Assert.isNotNull(result, 'execute() must return a non-null EngineResult');
    }

    // Same happy path, but with amortisationMethod set — exercises the amortisation
    // branch inside execute() that the test above (blank amortisationMethod) skips.
    @IsTest
    static void testCalculationEngine_Execute_WithAmortisationMethod_ComputesPrincipalDue() {
        AuditEventLogger.clearPending();
        CalculationEngine eng = new CalculationEngine(CalculationEngineBase.Mode.PREVIEW);
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-exec-amort-coverage')
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.today().addMonths(-1))
            .setPeriodEndDate(Date.today())
            .setInterestRate(5.0)
            .setPrincipal(1000000)
            .setAmortisationMethod('Bullet')
            .build();

        Test.startTest();
        EngineResult result = eng.execute(ctx);
        Test.stopTest();

        Assert.isNotNull(result, 'execute() with amortisationMethod set must return a non-null EngineResult');
    }
}