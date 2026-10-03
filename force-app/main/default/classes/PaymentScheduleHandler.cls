/**
 * PaymentScheduleHandler
 * Phase 1 trigger handler for Payment_Schedule__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class PaymentScheduleHandler extends LMSTriggerHandler {

    public PaymentScheduleHandler() {
        super('Payment_Schedule__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Payment_Schedule__c',
                String.valueOf(rec.Id), 'Payment Schedule created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        // Status transition audit
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') != oldRec.get('Status__c')) {
                AuditEventLogger.logManual('STATUS_CHANGED', 'Payment_Schedule__c',
                    String.valueOf(newRec.Id),
                    'Status: ' + oldRec.get('Status__c') + ' -> ' + newRec.get('Status__c'));
            }
        }
        AuditEventLogger.flush();
    }
}