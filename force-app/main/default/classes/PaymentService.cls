/**
 * PaymentService
 * Handles Payment_Transaction lifecycle:
 * - Cleared → runs waterfall allocation via IWaterfallAllocator against ordered schedule targets
 * - Reversed → delegates to PaymentAllocationReversalHandler (Rule R9 cascade)
 * Called from PaymentTransactionTrigger on afterUpdate when Status changes.
 */
public class PaymentService {

    public static void handleCleared(List<Payment_Transaction__c> txns, Map<Id,Payment_Transaction__c> oldMap) {
        List<Payment_Transaction__c> justCleared = new List<Payment_Transaction__c>();
        for (Payment_Transaction__c tx : txns) {
            if (tx.Status__c == 'Cleared' && oldMap.get(tx.Id).Status__c != 'Cleared') {
                justCleared.add(tx);
            }
        }
        if (justCleared.isEmpty()) return;

        // Pre-load DPs
        Set<Id> dpIds = new Set<Id>();
        for (Payment_Transaction__c tx : justCleared) dpIds.add(tx.Debt_Position__c);
        Map<Id,Debt_Position__c> dps = new Map<Id,Debt_Position__c>([
            SELECT Id, Outstanding_Balance__c, Waterfall_Rule__c
            FROM Debt_Position__c WHERE Id IN :dpIds
        ]);

        // Load all Due/Overdue Payment_Schedules per DP, ordered oldest first
        // Allocators iterate these in order and link each Payment_Allocation__c to its schedule
        Map<Id, List<Payment_Schedule__c>> dpSchedules = new Map<Id, List<Payment_Schedule__c>>();
        for (Id dpId : dpIds) dpSchedules.put(dpId, new List<Payment_Schedule__c>());
        for (Payment_Schedule__c ps : [
            SELECT Id, Debt_Position__c, Due_Date__c, Interest_Due__c, Principal_Due__c, Fees_Due__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c IN :dpIds
              AND Status__c IN ('Due', 'Overdue')
            ORDER BY Due_Date__c ASC
        ]) {
            dpSchedules.get(ps.Debt_Position__c).add(ps);
        }

        List<Payment_Allocation__c> allAllocations = new List<Payment_Allocation__c>();

        for (Payment_Transaction__c tx : justCleared) {
            Debt_Position__c dp = dps.get(tx.Debt_Position__c);
            String waterfallRule = String.isNotBlank(dp.Waterfall_Rule__c) ? dp.Waterfall_Rule__c : 'STANDARD';
            List<Payment_Schedule__c> scheduleTargets = dpSchedules.get(tx.Debt_Position__c);

            CalcContext ctx = new CalcContext.Builder()
                .setDebtPositionId(tx.Debt_Position__c)
                .setPrincipal(dp.Outstanding_Balance__c ?? 0)
                .setCorrelationId(TriggerContext.getInstance().correlationId)
                .setWaterfallRule(waterfallRule)
                .setExtras(new Map<String,Object>{
                    'paymentTransactionId'                  => String.valueOf(tx.Id),
                    'paymentAmount'                         => tx.Amount__c,
                    'outstanding_Penalty'                   => 0,
                    'outstanding_PIK_Interest_Cash_Portion' => 0,
                    'outstanding_Reserve_Replenishment'     => 0
                })
                .build();

            IWaterfallAllocator allocator = CalculationEngineFactory.getWaterfallAllocator(waterfallRule);
            EngineResult result = allocator.allocate(tx.Amount__c, ctx, scheduleTargets);
            allAllocations.addAll((List<Payment_Allocation__c>)(Object)result.recordsToInsert);
        }

        if (!allAllocations.isEmpty()) {
            TriggerContext.getInstance().bypassGuards = true;
            insert allAllocations;

            // After allocations are created, update each affected Payment_Schedule status:
            // fully covered → Paid, partially covered → Partial
            Map<Id, Decimal> scheduleAllocated = new Map<Id, Decimal>();
            for (Payment_Allocation__c alloc : allAllocations) {
                if (alloc.Payment_Schedule__c != null) {
                    scheduleAllocated.put(alloc.Payment_Schedule__c,
                        (scheduleAllocated.get(alloc.Payment_Schedule__c) ?? 0) + alloc.Amount__c);
                }
            }

            Map<Id, Payment_Schedule__c> allSchedules = new Map<Id, Payment_Schedule__c>();
            for (List<Payment_Schedule__c> psList : dpSchedules.values()) {
                for (Payment_Schedule__c ps : psList) allSchedules.put(ps.Id, ps);
            }

            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
            for (Id psId : scheduleAllocated.keySet()) {
                Payment_Schedule__c ps = allSchedules.get(psId);
                if (ps == null) continue;
                Decimal totalDue  = (ps.Interest_Due__c ?? 0) + (ps.Principal_Due__c ?? 0) + (ps.Fees_Due__c ?? 0);
                Decimal allocated = scheduleAllocated.get(psId);
                String newStatus  = allocated >= totalDue ? 'Paid' : 'Partial';
                schedulesToUpdate.add(new Payment_Schedule__c(Id = psId, Status__c = newStatus));
            }
            if (!schedulesToUpdate.isEmpty()) update schedulesToUpdate;

            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.flush();
    }

    public static void handleReversed(List<Payment_Transaction__c> txns, Map<Id,Payment_Transaction__c> oldMap) {
        List<Payment_Transaction__c> justReversed = new List<Payment_Transaction__c>();
        for (Payment_Transaction__c tx : txns) {
            if (tx.Status__c == 'Reversed' && oldMap.get(tx.Id).Status__c != 'Reversed') {
                justReversed.add(tx);
            }
        }
        if (!justReversed.isEmpty()) {
            PaymentAllocationReversalHandler.cascade(justReversed);
        }
    }
}