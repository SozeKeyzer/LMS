/**
 * PaymentAllocationHandler
 * Phase 1 trigger handler for Payment_Allocation__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class PaymentAllocationHandler extends LMSTriggerHandler {

    public PaymentAllocationHandler() {
        super('Payment_Allocation__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Payment_Allocation__c',
                String.valueOf(rec.Id), 'Payment Allocation created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        // Status change audit
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('PAYMENT_ALLOCATED','Payment_Allocation__c',
                String.valueOf(rec.Id),'Allocation updated: ' + rec.get('Status__c'));
        }
        AuditEventLogger.flush();
    }
}