/**
 * PaymentAllocationReversalHandler
 * Implements Rule R9 reversal cascade:
 * 1. Mark all Payment_Allocation__c records → Status = Reversed
 * 2. Revert Payment_Schedule status back to Due or Overdue
 * 3. Create Payment_Adjustment (Reversal type) per spec Rule R9 / Calc Engine Logic Part 11
 * 4. Create audit trail
 * NOTE: Outstanding_Balance__c is a formula field — not written directly.
 *       The formula recalculates automatically from disbursements and allocations.
 */
public class PaymentAllocationReversalHandler {

    public static void cascade(List<Payment_Transaction__c> reversedTxns) {
        if (reversedTxns.isEmpty()) return;

        Set<Id> txIds = new Map<Id,Payment_Transaction__c>(reversedTxns).keySet();

        // Step 1: Mark all active allocations as Reversed
        List<Payment_Allocation__c> allocations = [
            SELECT Id, Status__c, Payment_Transaction__c, Amount__c,
                   Component__c, Payment_Schedule__c
            FROM Payment_Allocation__c
            WHERE Payment_Transaction__c IN :txIds AND Status__c = 'Active'
        ];

        Set<Id> affectedScheduleIds = new Set<Id>();
        Map<Id,Id> txToSchedule = new Map<Id,Id>();
        List<Payment_Allocation__c> toUpdateAlloc = new List<Payment_Allocation__c>();

        for (Payment_Allocation__c alloc : allocations) {
            toUpdateAlloc.add(new Payment_Allocation__c(Id = alloc.Id, Status__c = 'Reversed'));
            if (alloc.Payment_Schedule__c != null) {
                affectedScheduleIds.add(alloc.Payment_Schedule__c);
                if (!txToSchedule.containsKey(alloc.Payment_Transaction__c)) {
                    txToSchedule.put(alloc.Payment_Transaction__c, alloc.Payment_Schedule__c);
                }
            }
        }

        TriggerContext.getInstance().bypassGuards = true;
        if (!toUpdateAlloc.isEmpty()) update toUpdateAlloc;

        // Step 2: Reset Payment_Schedule status
        if (!affectedScheduleIds.isEmpty()) {
            List<Payment_Schedule__c> schedules = [
                SELECT Id, Status__c, Due_Date__c
                FROM Payment_Schedule__c WHERE Id IN :affectedScheduleIds
            ];
            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
            for (Payment_Schedule__c ps : schedules) {
                String newStatus = ps.Due_Date__c < Date.today() ? 'Overdue' : 'Due';
                schedulesToUpdate.add(new Payment_Schedule__c(
                    Id = ps.Id, Status__c = newStatus
                ));
            }
            if (!schedulesToUpdate.isEmpty()) update schedulesToUpdate;
        }

        // Step 3: Create Payment_Adjustment (Reversal type) per Rule R9
        String corrId = TriggerContext.getInstance().correlationId;
        List<Payment_Adjustment__c> adjustments = new List<Payment_Adjustment__c>();
        for (Payment_Transaction__c tx : reversedTxns) {
            adjustments.add(new Payment_Adjustment__c(
                Adjustment_Type__c            = 'Reversal',
                Status__c                     = 'Approved',
                Linked_Payment_Transaction__c = tx.Id,
                Original_Schedule__c          = txToSchedule.get(tx.Id),
                Reason__c                     = tx.Reversal_Reason__c,
                Before_Amount__c              = tx.Amount__c,
                After_Amount__c               = 0,
                Adjustment_Date__c            = Date.today(),
                Effective_Date__c             = Date.today(),
                Source__c                     = 'System_Calculated',
                Correlation_Id__c             = corrId,
                Source_Note__c                = 'Auto-created on Payment_Transaction reversal: ' + tx.Id
            ));
        }
        if (!adjustments.isEmpty()) insert adjustments;

        TriggerContext.getInstance().bypassGuards = false;

        // Step 4: Audit
        for (Payment_Transaction__c tx : reversedTxns) {
            AuditEventLogger.logManual('PAYMENT_REVERSED', 'Payment_Transaction__c',
                String.valueOf(tx.Id),
                'Payment reversed. ' + toUpdateAlloc.size() + ' allocations marked Reversed. Schedule statuses reset. Reversal adjustment created.');
        }
        AuditEventLogger.flush();
    }
}