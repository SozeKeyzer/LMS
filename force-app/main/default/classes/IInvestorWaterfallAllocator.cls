/**
 * IInvestorWaterfallAllocator — Phase 3 interface stub
 * Full syndicated-lending capabilities (Distribution_Allocation__c, Holder_Economics__c,
 * Position_Allocation__c) are deferred per Spec v7 Part 7A.3.
 * This stub compiles without referencing undeployed SObjects.
 */
public interface IInvestorWaterfallAllocator {
    /**
     * Distribute a single Payment_Allocation across all holders of a Debt_Position.
     * Returns a list of SObject records (Distribution_Allocation__c when deployed).
     */
    List<SObject> distribute(
        Payment_Allocation__c borrowerAllocation,
        List<SObject> holders,
        List<SObject> economics
    );
}