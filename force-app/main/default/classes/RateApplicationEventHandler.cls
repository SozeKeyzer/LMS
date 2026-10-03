/**
 * RateApplicationEventHandler
 * Phase 1 trigger handler for Rate_Application_Event__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class RateApplicationEventHandler extends LMSTriggerHandler {

    public RateApplicationEventHandler() {
        super('Rate_Application_Event__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Rate_Application_Event__c',
                String.valueOf(rec.Id), 'Rate Application Event created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        // Update parent IRT Application_Status when decision recorded
        for (SObject rec : newList) {
            AuditEventLogger.logManual('RATE_APPLIED','Rate_Application_Event__c',
                String.valueOf(rec.Id),'Rate decision: ' + rec.get('Decision_Type__c'));
        }
        AuditEventLogger.flush();
    }
}