@IsTest
private class FlowBypassActionTest {

    @TestSetup
    static void setup() { TriggerContext.reset(); }

    @IsTest
    static void testSetBypass_TrueInput_SetsFlag() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(new List<Boolean>{ true });
        Assert.isTrue(TriggerContext.getInstance().bypassGuards,
            'bypassGuards must be true after setBypassGuards(true)');
    }

    @IsTest
    static void testSetBypass_FalseInput_ClearsFlag() {
        TriggerContext.getInstance().bypassGuards = true;
        FlowBypassAction.setBypassGuards(new List<Boolean>{ false });
        Assert.isFalse(TriggerContext.getInstance().bypassGuards,
            'bypassGuards must be false after setBypassGuards(false)');
    }

    @IsTest
    static void testSetBypass_NullList_DefaultsToTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(null);
        Assert.isTrue(TriggerContext.getInstance().bypassGuards,
            'Null input list must default to true');
    }

    @IsTest
    static void testSetBypass_EmptyList_DefaultsToTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(new List<Boolean>());
        Assert.isTrue(TriggerContext.getInstance().bypassGuards,
            'Empty input list must default to true');
    }

    @IsTest
    static void testSetBypass_NullElement_DefaultsToTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(new List<Boolean>{ null });
        Assert.isTrue(TriggerContext.getInstance().bypassGuards,
            'Null element in list must default to true');
    }
}