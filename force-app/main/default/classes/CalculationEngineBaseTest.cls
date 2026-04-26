@IsTest
private class CalculationEngineBaseTest {

    private class TestEngine extends CalculationEngineBase {
        public TestEngine(Mode m) { super(m); }
        public override EngineResult execute(CalcContext ctx) {
            EngineResult r = new EngineResult();
            r.setAmount(100);
            return r;
        }
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
}
