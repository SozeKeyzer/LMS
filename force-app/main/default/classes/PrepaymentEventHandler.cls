/**
 * PrepaymentEventHandler
 * Trigger handler for Prepayment_Event__c.
 * afterInsert: logs RECORD_CREATED audit event.
 * afterUpdate: logs STATUS_CHANGED when Status transitions.
 * Break cost computation is triggered explicitly via BreakCostCalculator.calculateFromFlow().
 */
public class PrepaymentEventHandler extends LMSTriggerHandler {

    public PrepaymentEventHandler() {
        super('Prepayment_Event__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Prepayment_Event__c',
                String.valueOf(rec.Id), 'Prepayment Event created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') != null &&
                newRec.get('Status__c') != oldRec.get('Status__c')) {
                AuditEventLogger.logManual('STATUS_CHANGED', 'Prepayment_Event__c',
                    String.valueOf(newRec.Id),
                    'Prepayment Event status: ' + oldRec.get('Status__c') + ' -> ' + newRec.get('Status__c'));
            }
        }
        AuditEventLogger.flush();
    }
}