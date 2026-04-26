/**
 * LMSTriggerHandler
 * Abstract base for all LMS trigger handlers.
 * Provides: context switches, bypass flag, Correlation ID propagation.
 * Each concrete handler overrides only the methods it needs.
 */
public abstract class LMSTriggerHandler {

    protected String objectApiName;

    public LMSTriggerHandler(String objectApiName) {
        this.objectApiName = objectApiName;
    }

    /** Entry point called by every trigger. */
    public void run() {
        // Propagate Correlation ID across this transaction
        TriggerContext ctx = TriggerContext.getInstance();

        if (Trigger.isBefore) {
            if (Trigger.isInsert)  beforeInsert(Trigger.new);
            if (Trigger.isUpdate)  {
                ProtectedFieldGuardHandler.enforce(objectApiName, Trigger.new, Trigger.oldMap);
                beforeUpdate(Trigger.new, Trigger.oldMap);
            }
            if (Trigger.isDelete)  beforeDelete(Trigger.old);
        } else {
            if (Trigger.isInsert)  afterInsert(Trigger.new, Trigger.newMap);
            if (Trigger.isUpdate)  afterUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
            if (Trigger.isDelete)  afterDelete(Trigger.old, Trigger.oldMap);
            if (Trigger.isUndelete) afterUndelete(Trigger.new, Trigger.newMap);
        }
    }

    // Default no-op implementations — override only what you need
    protected virtual void beforeInsert(List<SObject> newList)                                     {}
    protected virtual void beforeUpdate(List<SObject> newList, Map<Id,SObject> oldMap)             {}
    protected virtual void beforeDelete(List<SObject> oldList)                                     {}
    protected virtual void afterInsert(List<SObject> newList, Map<Id,SObject> newMap)              {}
    protected virtual void afterUpdate(List<SObject> newList, Map<Id,SObject> newMap,
                                       List<SObject> oldList, Map<Id,SObject> oldMap)              {}
    protected virtual void afterDelete(List<SObject> oldList, Map<Id,SObject> oldMap)              {}
    protected virtual void afterUndelete(List<SObject> newList, Map<Id,SObject> newMap)            {}
}
