/**
 * StandardInvestorWaterfallAllocator — Phase 3 stub
 * Pro-rata distribution across holders is deferred until Distribution_Allocation__c,
 * Holder_Economics__c, and Position_Allocation__c are deployed (Spec v7 Part 7A.3).
 * Stub returns empty list; full implementation to follow in Phase 3 metadata deployment.
 */
public class StandardInvestorWaterfallAllocator implements IInvestorWaterfallAllocator {

    public List<SObject> distribute(
        Payment_Allocation__c borrowerAllocation,
        List<SObject> holders,
        List<SObject> economics
    ) {
        if (holders == null || holders.isEmpty()) return new List<SObject>();

        AuditEventLogger.logEngine(
            'PAYMENT_ALLOCATED', 'Payment_Allocation__c',
            String.valueOf(borrowerAllocation.Id),
            'StandardInvestorWaterfallAllocator: ' + holders.size()
                + ' holder(s) — Distribution_Allocation__c not yet deployed, returning empty.'
        );
        AuditEventLogger.flush();
        return new List<SObject>();
    }
}