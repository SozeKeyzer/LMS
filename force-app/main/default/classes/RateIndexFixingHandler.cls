/**
 * RateIndexFixingHandler
 * Phase 1 trigger handler for Rate_Index_Fixing__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class RateIndexFixingHandler extends LMSTriggerHandler {

    public RateIndexFixingHandler() {
        super('Rate_Index_Fixing__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Rate_Index_Fixing__c',
                String.valueOf(rec.Id), 'Rate Index Fixing created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        AuditEventLogger.flush();
    }
}