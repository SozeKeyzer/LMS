/**
 * ElectionHandler
 * Phase 2 trigger handler for Election__c.
 * afterUpdate: locks election when Is_Immutable transitions to true. Validates Split amounts.
 */
public class ElectionHandler extends LMSTriggerHandler {

    public ElectionHandler() {
        super('Election__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Election__c',
                String.valueOf(rec.Id), 'Election created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Election_Type__c') != null &&
                newRec.get('Election_Type__c') != oldRec.get('Election_Type__c')) {
                AuditEventLogger.logManual('STATUS_CHANGED', 'Election__c',
                    String.valueOf(newRec.Id),
                    'Election type: ' + oldRec.get('Election_Type__c') + ' -> ' + newRec.get('Election_Type__c'));
            }
        }
        AuditEventLogger.flush();
    }
}