/**
 * IWaterfallAllocator
 * Implemented by: StandardWaterfallAllocator, CashSweepWaterfallAllocator,
 * DefaultEventWaterfallAllocator (Phase 1), IInvestorWaterfallAllocator (Phase 3)
 */
public interface IWaterfallAllocator {
    /**
     * Allocate a payment amount across penalty, fee, interest, and principal buckets
     * according to the waterfall priority order defined in Waterfall_Rule__mdt.
     * @param paymentAmount  Total cash received
     * @param ctx            CalcContext with outstanding amounts per bucket in extras map
     * @return               EngineResult with recordsToInsert = Payment_Allocation__c records
     */
    EngineResult allocate(Decimal paymentAmount, CalcContext ctx);
}
