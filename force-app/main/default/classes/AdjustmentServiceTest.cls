/**
 * AdjustmentServiceTest
 * Covers AdjustmentService.handleEffective():
 *   1. No transitions to Effective → no-op (Net_Due__c unchanged)
 *   2. 4-eyes violation (Requested_By == Approved_By) → addError, Net_Due__c unchanged
 *   3. Valid adjustment (different users or null Approved_By) → Net_Due__c updated by Delta__c
 *
 * AdjustmentService is called from the Payment_Adjustment__c trigger handler.
 * We invoke it directly (passing the adjustment list + oldMap) to stay
 * trigger-free and test the service logic in isolation.
 */
@IsTest
private class AdjustmentServiceTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(
            Name = 'Adj FI', Status__c = 'Active');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Adj DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'ADJSVC001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(-1),
            Period_End__c     = Date.today(),
            Due_Date__c       = Date.today(),
            Status__c         = 'Due',
            Principal_Due__c  = 100000,
            Interest_Due__c   = 5000,
            Fees_Due__c       = 0,
            Net_Due__c        = 105000,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'ADJ-PS-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ── No Effective transitions → no-op ─────────────────────────────────────

    @IsTest
    static void testHandleEffective_NoTransitions_NetDueUnchanged() {
        Payment_Schedule__c ps = [SELECT Id, Net_Due__c FROM Payment_Schedule__c LIMIT 1];

        // Both adj and oldAdj have Status = Pending — no transition to Effective
        TriggerContext.getInstance().bypassGuards = true;
        Payment_Adjustment__c adj = new Payment_Adjustment__c(
            Original_Schedule__c = ps.Id,
            Before_Amount__c     = 0,
            After_Amount__c      = 500,
            Status__c            = 'Draft',
            Reason__c            = 'Test adjustment',
            Adjustment_Date__c   = Date.today(),
            Effective_Date__c    = Date.today(),
            Requested_By__c      = UserInfo.getUserId()
        );
        insert adj;
        TriggerContext.getInstance().bypassGuards = false;

        Payment_Adjustment__c oldAdj = adj.clone(true, true, false, false);
        oldAdj.Status__c = 'Draft';

        Test.startTest();
        AdjustmentService.handleEffective(
            new List<Payment_Adjustment__c>{ adj },
            new Map<Id, Payment_Adjustment__c>{ adj.Id => oldAdj }
        );
        Test.stopTest();

        Payment_Schedule__c psAfter = [SELECT Net_Due__c FROM Payment_Schedule__c WHERE Id = :ps.Id];
        Assert.areEqual(ps.Net_Due__c, psAfter.Net_Due__c, 'No transition → Net_Due__c must not change');
    }

    // ── 4-eyes violation (Requested_By == Approved_By) → addError ────────────

    @IsTest
    static void testHandleEffective_FourEyesViolation_NetDueUnchanged() {
        Payment_Schedule__c ps = [SELECT Id, Net_Due__c FROM Payment_Schedule__c LIMIT 1];
        Id userId = UserInfo.getUserId();

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Adjustment__c adj = new Payment_Adjustment__c(
            Original_Schedule__c = ps.Id,
            Before_Amount__c     = 0,
            After_Amount__c      = 1000,
            Status__c            = 'Draft',
            Reason__c            = 'Test adjustment',
            Adjustment_Date__c   = Date.today(),
            Effective_Date__c    = Date.today(),
            Requested_By__c      = userId
        );
        insert adj;
        TriggerContext.getInstance().bypassGuards = false;

        // Simulate trigger: old is Pending, new is Effective; Requested_By = Approved_By (same user)
        Payment_Adjustment__c newAdj = adj.clone(true, true, false, false);
        newAdj.Status__c      = 'Effective';
        newAdj.Requested_By__c = userId;
        newAdj.Approved_By__c  = userId; // same user = 4-eyes violation

        Payment_Adjustment__c oldAdj = adj.clone(true, true, false, false);
        oldAdj.Status__c = 'Draft';

        Test.startTest();
        AdjustmentService.handleEffective(
            new List<Payment_Adjustment__c>{ newAdj },
            new Map<Id, Payment_Adjustment__c>{ adj.Id => oldAdj }
        );
        Test.stopTest();

        // 4-eyes violation: addError is called on the adj; schedule must be untouched
        Payment_Schedule__c psAfter = [SELECT Net_Due__c FROM Payment_Schedule__c WHERE Id = :ps.Id];
        Assert.areEqual(ps.Net_Due__c, psAfter.Net_Due__c,
            '4-eyes violation must not update Net_Due__c');
    }

    // ── Valid adjustment (null Approved_By) → Net_Due__c updated by Delta__c ─

    @IsTest
    static void testHandleEffective_ValidAdjustment_NetDueUpdated() {
        Payment_Schedule__c ps = [SELECT Id, Net_Due__c FROM Payment_Schedule__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Adjustment__c adj = new Payment_Adjustment__c(
            Original_Schedule__c = ps.Id,
            Before_Amount__c     = 0,
            After_Amount__c      = 2500,
            Status__c            = 'Draft',
            Reason__c            = 'Test adjustment',
            Adjustment_Date__c   = Date.today(),
            Effective_Date__c    = Date.today(),
            Requested_By__c      = UserInfo.getUserId()
        );
        insert adj;
        TriggerContext.getInstance().bypassGuards = false;

        // Re-query to get the formula field Delta__c populated from the database
        adj = [SELECT Id, Original_Schedule__c, Status__c, Requested_By__c,
                      Approved_By__c, Before_Amount__c, After_Amount__c, Delta__c
               FROM Payment_Adjustment__c WHERE Id = :adj.Id];

        // Simulate trigger: Status transitions from Pending → Effective
        // Approved_By__c is null (different from Requested_By — 4-eyes passes)
        Payment_Adjustment__c newAdj = adj.clone(true, true, false, false);
        newAdj.Status__c       = 'Effective';
        newAdj.Approved_By__c  = null; // null != Requested_By → 4-eyes passes

        Payment_Adjustment__c oldAdj = adj.clone(true, true, false, false);
        oldAdj.Status__c = 'Draft';

        Decimal baseNetDue = ps.Net_Due__c;

        Test.startTest();
        AdjustmentService.handleEffective(
            new List<Payment_Adjustment__c>{ newAdj },
            new Map<Id, Payment_Adjustment__c>{ adj.Id => oldAdj }
        );
        Test.stopTest();

        Payment_Schedule__c psAfter = [SELECT Net_Due__c FROM Payment_Schedule__c WHERE Id = :ps.Id];
        Assert.areEqual(baseNetDue + 2500, psAfter.Net_Due__c,
            'Valid adjustment must increase Net_Due__c by Delta__c');
    }
}