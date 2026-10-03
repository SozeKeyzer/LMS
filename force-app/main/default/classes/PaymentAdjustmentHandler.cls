/**
 * PaymentAdjustmentHandler
 * Phase 1 trigger handler for Payment_Adjustment__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class PaymentAdjustmentHandler extends LMSTriggerHandler {

    public PaymentAdjustmentHandler() {
        super('Payment_Adjustment__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Payment_Adjustment__c',
                String.valueOf(rec.Id), 'Payment Adjustment created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        AdjustmentService.handleEffective(
            (List<Payment_Adjustment__c>)(Object)newList,
            (Map<Id,Payment_Adjustment__c>)(Object)oldMap);
    }
}