/**
 * LMSWaterfallInvestorTest
 * Phase 3 stub tests for StandardInvestorWaterfallAllocator.
 * Full pro-rata distribution tests deferred until Distribution_Allocation__c,
 * Position_Allocation__c, and Holder_Economics__c are deployed (Spec v7 Part 7A.3).
 */
@IsTest
private class LMSWaterfallInvestorTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Waterfall FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'Waterfall DP', Financial_Instrument__c = fi.Id, Status__c = 'Active',
            Position_Notional__c = 1000000, iPlatform_External_Id__c = 'WFALL-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Transaction__c pt = new Payment_Transaction__c(
            Debt_Position__c    = dp.Id,
            Amount__c           = 100000,
            Transaction_Date__c = Date.today(),
            Value_Date__c       = Date.today()
        );
        insert pt;

        Payment_Allocation__c pa = new Payment_Allocation__c(
            Amount__c              = 100000,
            Component__c           = 'Principal',
            Status__c              = 'Active',
            Source__c              = 'System_Calculated',
            Allocation_Order__c    = 1,
            Payment_Transaction__c = pt.Id
        );
        insert pa;
        TriggerContext.getInstance().bypassGuards = false;
    }

    @IsTest
    static void testDistribute_EmptyHolders_ReturnsEmpty() {
        Payment_Allocation__c ba = [SELECT Id FROM Payment_Allocation__c LIMIT 1];
        StandardInvestorWaterfallAllocator alloc = new StandardInvestorWaterfallAllocator();

        Test.startTest();
        List<SObject> results = alloc.distribute(ba, new List<SObject>(), new List<SObject>());
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Phase 3 stub should return empty list for empty holders');
    }

    @IsTest
    static void testDistribute_WithHolderPlaceholder_ReturnsEmptyStub() {
        Payment_Allocation__c ba = [SELECT Id FROM Payment_Allocation__c LIMIT 1];
        StandardInvestorWaterfallAllocator alloc = new StandardInvestorWaterfallAllocator();

        Test.startTest();
        List<SObject> results = alloc.distribute(ba, new List<SObject>{ ba }, new List<SObject>());
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Phase 3 stub returns empty until Distribution_Allocation__c deployed');
    }

    @IsTest
    static void testDistribute_NoException() {
        Payment_Allocation__c ba = [SELECT Id FROM Payment_Allocation__c LIMIT 1];
        StandardInvestorWaterfallAllocator alloc = new StandardInvestorWaterfallAllocator();
        Boolean threw = false;

        Test.startTest();
        try {
            alloc.distribute(ba, new List<SObject>(), new List<SObject>());
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'StandardInvestorWaterfallAllocator stub must not throw');
    }
}