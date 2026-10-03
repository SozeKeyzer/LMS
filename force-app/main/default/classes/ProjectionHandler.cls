/**
 * ProjectionHandler
 * Phase 1 trigger handler for Projection__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class ProjectionHandler extends LMSTriggerHandler {

    public ProjectionHandler() {
        super('Projection__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Projection__c',
                String.valueOf(rec.Id), 'Projection created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') != oldRec.get('Status__c')) {
                AuditEventLogger.logEngine('STATUS_CHANGED','Projection__c',
                    String.valueOf(newRec.Id),'Projection: ' + newRec.get('Status__c'));
            }
        }
        AuditEventLogger.flush();
    }
}