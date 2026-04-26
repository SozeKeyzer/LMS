@IsTest
private class TriggerContextTest {

    @TestSetup
    static void setup() { TriggerContext.reset(); }

    @IsTest
    static void testSingletonReturnsSameInstance() {
        TriggerContext a = TriggerContext.getInstance();
        TriggerContext b = TriggerContext.getInstance();
        Assert.areEqual(a.correlationId, b.correlationId, 'Should be same instance');
    }

    @IsTest
    static void testCorrelationIdIsValidUuid() {
        String cid = TriggerContext.getInstance().correlationId;
        Assert.isTrue(cid.length() == 36, 'UUID should be 36 chars, got: ' + cid.length());
        Assert.isTrue(cid.contains('-'), 'UUID should contain dashes');
    }

    @IsTest
    static void testModeSetCorrectly() {
        TriggerContext ctx = TriggerContext.getInstance();
        ctx.setMode(TriggerContext.EngineMode.PREVIEW);
        Assert.areEqual(TriggerContext.EngineMode.PREVIEW, ctx.mode);
        ctx.setMode(TriggerContext.EngineMode.APPLY);
        Assert.areEqual(TriggerContext.EngineMode.APPLY, ctx.mode);
    }

    @IsTest
    static void testResetCreatesNewInstance() {
        String firstId = TriggerContext.getInstance().correlationId;
        TriggerContext.reset();
        String secondId = TriggerContext.getInstance().correlationId;
        Assert.areNotEqual(firstId, secondId, 'Reset should create a new correlation ID');
    }
}
