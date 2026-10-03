/**
 * StandardWaterfallAllocator — implements IWaterfallAllocator
 * Standard order: Penalty → Fee → Interest → PIK_Interest_Cash_Portion → Principal → Reserve_Replenishment
 * Iterates scheduleTargets (oldest due date first), linking each allocation to its schedule.
 * Components not on the schedule (Penalty, PIK, Reserve) fall back to ctx.extras.
 */
public class StandardWaterfallAllocator extends CalculationEngineBase implements IWaterfallAllocator {

    private static final List<String> WATERFALL_ORDER = new List<String>{
        'Penalty', 'Fee', 'Interest', 'PIK_Interest_Cash_Portion', 'Principal', 'Reserve_Replenishment'
    };

    public StandardWaterfallAllocator() { super(Mode.APPLY); }

    public EngineResult allocate(Decimal paymentAmount, CalcContext ctx, List<Payment_Schedule__c> scheduleTargets) {
        EngineResult result = new EngineResult();
        Decimal remaining = paymentAmount;
        Integer order = 1;
        String txId = (String) ctx.extras.get('paymentTransactionId');

        if (scheduleTargets != null && !scheduleTargets.isEmpty()) {
            for (Payment_Schedule__c ps : scheduleTargets) {
                if (remaining <= 0) break;
                for (String component : WATERFALL_ORDER) {
                    if (remaining <= 0) break;
                    Decimal outstanding = scheduleOutstanding(ps, component, ctx);
                    if (outstanding <= 0) continue;
                    Decimal allocated = remaining >= outstanding ? outstanding : remaining;
                    remaining -= allocated;
                    result.addInsert(new Payment_Allocation__c(
                        Payment_Transaction__c = txId,
                        Payment_Schedule__c    = ps.Id,
                        Component__c           = component,
                        Amount__c              = allocated,
                        Allocation_Order__c    = order++,
                        Status__c              = 'Active',
                        Waterfall_Rule_Used__c = 'STANDARD',
                        Correlation_Id__c      = ctx.correlationId,
                        Source__c              = 'System_Calculated'
                    ));
                }
            }
        } else {
            for (String component : WATERFALL_ORDER) {
                if (remaining <= 0) break;
                Decimal outstanding = (Decimal)(ctx.extras.get('outstanding_' + component) ?? 0);
                if (outstanding <= 0) continue;
                Decimal allocated = remaining >= outstanding ? outstanding : remaining;
                remaining -= allocated;
                result.addInsert(new Payment_Allocation__c(
                    Payment_Transaction__c = txId,
                    Component__c           = component,
                    Amount__c              = allocated,
                    Allocation_Order__c    = order++,
                    Status__c              = 'Active',
                    Waterfall_Rule_Used__c = 'STANDARD',
                    Correlation_Id__c      = ctx.correlationId,
                    Source__c              = 'System_Calculated'
                ));
            }
        }

        result.setAmount(paymentAmount - remaining);
        result.putMeta('unallocated', remaining);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) {
        return allocate((Decimal)(ctx.extras.get('paymentAmount') ?? 0), ctx, new List<Payment_Schedule__c>());
    }

    private static Decimal scheduleOutstanding(Payment_Schedule__c ps, String component, CalcContext ctx) {
        if (component == 'Interest')  return ps.Interest_Due__c  ?? 0;
        if (component == 'Principal') return ps.Principal_Due__c ?? 0;
        if (component == 'Fee')       return ps.Fees_Due__c      ?? 0;
        return (Decimal)(ctx.extras.get('outstanding_' + component) ?? 0);
    }
}