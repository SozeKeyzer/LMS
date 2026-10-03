/**
 * FlowBypassAction
 * Invocable action called by After-Save flows before performing DML on
 * fields protected by ProtectedFieldGuardHandler. Sets bypassGuards on the
 * per-transaction TriggerContext singleton so the guard skips enforcement
 * for the remainder of the transaction — flows are trusted system actors.
 */
public class FlowBypassAction {

    @InvocableMethod(
        label='Set Guard Bypass'
        description='Enables or disables ProtectedFieldGuardHandler bypass for the current transaction. Call with true before flow-initiated DML on protected fields.'
        category='LMS'
    )
    public static void setBypassGuards(List<Boolean> inputs) {
        Boolean bypass = (inputs != null && !inputs.isEmpty() && inputs[0] != null)
            ? inputs[0] : true;
        TriggerContext.getInstance().bypassGuards = bypass;
    }
}