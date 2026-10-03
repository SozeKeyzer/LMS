/**
 * IWaterfallAllocator
 * Implemented by: StandardWaterfallAllocator, CashSweepWaterfallAllocator,
 * DefaultEventWaterfallAllocator (Phase 1), IInvestorWaterfallAllocator (Phase 3)
 */
public interface IWaterfallAllocator {
    /**
     * Allocate a payment amount across penalty, fee, interest, and principal buckets.
     * Iterates scheduleTargets in order (oldest first), creating one Payment_Allocation__c
     * per component per schedule. For components not tracked on the schedule (Penalty, PIK,
     * Reserve) the allocator falls back to ctx.extras.
     * @param paymentAmount    Total cash received
     * @param ctx              CalcContext (correlationId, waterfallRule, extras for non-schedule buckets)
     * @param scheduleTargets  Ordered list of Payment_Schedule__c to allocate against
     * @return                 EngineResult with recordsToInsert = Payment_Allocation__c records
     */
    EngineResult allocate(Decimal paymentAmount, CalcContext ctx, List<Payment_Schedule__c> scheduleTargets);
}