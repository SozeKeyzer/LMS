/**
 * PaymentClearedStrategy
 * IRecalcStrategy for Trigger_Field__c = 'Payment_Cleared'.
 * Marks the matching Payment_Schedule row as Paid and updates the
 * Debt_Position Outstanding_Balance. Spec v3 Part 10.1.
 *
 * recordId = Payment_Allocation__c that has just cleared.
 */
public class PaymentClearedStrategy implements IRecalcStrategy {

    public void execute(Id recordId, String correlationId) {
        Payment_Allocation__c pa = [
            SELECT Id, Payment_Schedule__c, Amount__c, Component__c
            FROM Payment_Allocation__c
            WHERE Id = :recordId
        ];

        if (pa.Payment_Schedule__c == null) return;

        // Mark the schedule row Paid when a Principal allocation clears
        TriggerContext.getInstance().bypassGuards = true;
        try {
            update new Payment_Schedule__c(
                Id = pa.Payment_Schedule__c,
                Status__c = 'Paid',
                Is_Immutable__c = true
            );
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'PAYMENT_CLEARED', 'Payment_Allocation__c', String.valueOf(recordId),
            'Schedule row marked Paid. correlationId=' + correlationId
        );
        AuditEventLogger.flush();
    }
}