/**
 * PaymentTransactionHandler
 * Phase 1 trigger handler for Payment_Transaction__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class PaymentTransactionHandler extends LMSTriggerHandler {

    public PaymentTransactionHandler() {
        super('Payment_Transaction__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Payment_Transaction__c',
                String.valueOf(rec.Id), 'Payment Transaction created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        PaymentService.handleCleared(
            (List<Payment_Transaction__c>)(Object)newList,
            (Map<Id,Payment_Transaction__c>)(Object)oldMap);
        PaymentService.handleReversed(
            (List<Payment_Transaction__c>)(Object)newList,
            (Map<Id,Payment_Transaction__c>)(Object)oldMap);
    }
}