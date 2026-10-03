/**
 * LMSWaterfallTest
 * Phase 3 spec compliance tests for waterfall allocation strategies.
 *
 * Spec Part 7.5 worked example (Standard waterfall):
 *   Receipt AUD 100,000. Schedule: Penalty 0, Fee 5,000, Interest 80,000, Principal 50,000.
 *   Expected allocation: Fee 5K, Interest 80K, Principal 15K (shortfall 35K).
 *
 * Spec Part 7.3: CashSweep order = Penalty → Fee → Principal → Interest → PIK_Cash.
 *   vs Standard order = Penalty → Fee → Interest → PIK_Cash → Principal.
 */
@IsTest
private class LMSWaterfallTest {

    // Builds a CalcContext using the extras-based path (no Payment_Schedule records needed).
    private static CalcContext buildCtx(Map<String,Object> outstandings) {
        Map<String,Object> extras = new Map<String,Object>(outstandings);
        extras.put('paymentTransactionId', null); // null is safe — no DML in unit test
        return new CalcContext.Builder()
            .setCorrelationId('test-waterfall')
            .setExtras(extras)
            .build();
    }

    // Extracts the allocation components from EngineResult.recordsToInsert in insertion order.
    private static List<String> allocationComponents(EngineResult result) {
        List<String> components = new List<String>();
        for (SObject s : result.recordsToInsert) {
            components.add((String) s.get('Component__c'));
        }
        return components;
    }

    private static Decimal allocationAmount(EngineResult result, String component) {
        for (SObject s : result.recordsToInsert) {
            if (s.get('Component__c') == component) return (Decimal) s.get('Amount__c');
        }
        return null;
    }

    // ── Standard waterfall — Spec Part 7.5 worked example ────────────────────

    @IsTest
    static void testStandard_SpecPart75_AllocationOrder() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'               => 0,
            'outstanding_Fee'                   => 5000,
            'outstanding_Interest'              => 80000,
            'outstanding_Principal'             => 50000,
            'outstanding_PIK_Interest_Cash_Portion' => 0,
            'outstanding_Reserve_Replenishment' => 0
        };
        CalcContext ctx = buildCtx(outstanding);

        StandardWaterfallAllocator alloc = new StandardWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.isTrue(result.success);
        List<String> components = allocationComponents(result);
        Assert.isFalse(components.contains('Penalty'),
            'Spec 7.5: Penalty=0, no allocation row should be created');
        Assert.areEqual('Fee',      components[0], 'Standard order: Fee first');
        Assert.areEqual('Interest', components[1], 'Standard order: Interest second');
        Assert.areEqual('Principal',components[2], 'Standard order: Principal third');
        Assert.areEqual(3, components.size(), 'Only 3 non-zero components');
    }

    @IsTest
    static void testStandard_SpecPart75_AllocationAmounts() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'               => 0,
            'outstanding_Fee'                   => 5000,
            'outstanding_Interest'              => 80000,
            'outstanding_Principal'             => 50000,
            'outstanding_PIK_Interest_Cash_Portion' => 0,
            'outstanding_Reserve_Replenishment' => 0
        };
        CalcContext ctx = buildCtx(outstanding);

        StandardWaterfallAllocator alloc = new StandardWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        // Spec Part 7.5: Fee 5K, Interest 80K, Principal min(15K,50K)=15K
        Assert.areEqual(5000,  allocationAmount(result, 'Fee'),      'Fee fully funded: 5,000');
        Assert.areEqual(80000, allocationAmount(result, 'Interest'),  'Interest fully funded: 80,000');
        Assert.areEqual(15000, allocationAmount(result, 'Principal'), 'Principal partial: 15,000 (shortfall 35,000)');
        Assert.areEqual(100000, result.calculatedAmount, 'Total allocated = 100,000');
        Assert.areEqual(0, (Decimal) result.metadata.get('unallocated'), 'Nothing left unallocated');
    }

    @IsTest
    static void testStandard_PartialPayment_UnallocatedTracked() {
        // 50K payment against 80K interest due only
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Interest'  => 80000,
            'outstanding_Principal' => 20000
        };
        CalcContext ctx = buildCtx(outstanding);

        StandardWaterfallAllocator alloc = new StandardWaterfallAllocator();
        EngineResult result = alloc.allocate(50000, ctx, new List<Payment_Schedule__c>());

        Assert.areEqual(50000, allocationAmount(result, 'Interest'),
            '50K fully covers part of 80K interest');
        Assert.areEqual(null, allocationAmount(result, 'Principal'),
            'No funds left for Principal');
        Assert.areEqual(0, (Decimal) result.metadata.get('unallocated'), 'Fully allocated');
        Assert.areEqual(50000, result.calculatedAmount);
    }

    // ── CashSweep waterfall — Spec Part 7.3 order ────────────────────────────

    // CashSweep order: Penalty → Fee → Principal → Interest → PIK_Cash
    // Standard order: Penalty → Fee → Interest → PIK_Cash → Principal
    // Key difference: Fee and Principal swap; Principal comes BEFORE Interest in CashSweep.
    @IsTest
    static void testCashSweep_FeeBeforePrincipal() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 0,
            'outstanding_Fee'       => 5000,
            'outstanding_Principal' => 80000,
            'outstanding_Interest'  => 20000
        };
        CalcContext ctx = buildCtx(outstanding);

        CashSweepWaterfallAllocator alloc = new CashSweepWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        List<String> components = allocationComponents(result);
        Assert.areEqual('Fee',       components[0], 'CashSweep: Fee must come before Principal');
        Assert.areEqual('Principal', components[1], 'CashSweep: Principal before Interest');
        Assert.areEqual('Interest',  components[2], 'CashSweep: Interest last of funded components');
    }

    @IsTest
    static void testCashSweep_PrincipalBeforeInterest_Amounts() {
        // 100K payment: Fee 5K, Principal 80K → leaves 15K for Interest (20K due)
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Fee'       => 5000,
            'outstanding_Principal' => 80000,
            'outstanding_Interest'  => 20000
        };
        CalcContext ctx = buildCtx(outstanding);

        CashSweepWaterfallAllocator alloc = new CashSweepWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.areEqual(5000,  allocationAmount(result, 'Fee'),       'Fee: 5,000');
        Assert.areEqual(80000, allocationAmount(result, 'Principal'),  'Principal: 80,000 (full)');
        Assert.areEqual(15000, allocationAmount(result, 'Interest'),   'Interest: 15,000 (partial — Principal absorbed 80K first)');
        Assert.areEqual(0, (Decimal) result.metadata.get('unallocated'));
    }

    // Contrast: same inputs under Standard waterfall produce different allocation.
    // Standard: Interest funded in full (80K) before Principal (0K funded).
    @IsTest
    static void testStandardVsCashSweep_DifferentOutcomes() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Fee'       => 5000,
            'outstanding_Principal' => 80000,
            'outstanding_Interest'  => 20000
        };
        CalcContext stdCtx   = buildCtx(outstanding);
        CalcContext sweepCtx = buildCtx(outstanding);

        StandardWaterfallAllocator  std   = new StandardWaterfallAllocator();
        CashSweepWaterfallAllocator sweep = new CashSweepWaterfallAllocator();

        EngineResult stdResult   = std.allocate(100000, stdCtx, new List<Payment_Schedule__c>());
        EngineResult sweepResult = sweep.allocate(100000, sweepCtx, new List<Payment_Schedule__c>());

        // Standard: Interest fully funded (20K), Principal gets 75K
        Assert.areEqual(20000, allocationAmount(stdResult, 'Interest'),
            'Standard: Interest fully funded before Principal');
        Assert.areEqual(75000, allocationAmount(stdResult, 'Principal'),
            'Standard: Principal gets remaining 75K');

        // CashSweep: Principal fully funded (80K), Interest gets only 15K
        Assert.areEqual(80000, allocationAmount(sweepResult, 'Principal'),
            'CashSweep: Principal fully funded before Interest');
        Assert.areEqual(15000, allocationAmount(sweepResult, 'Interest'),
            'CashSweep: Interest gets remaining 15K only');
    }

    // Waterfall completeness invariant (spec Part 14.2): sum of allocations = payment amount exactly.
    @IsTest
    static void testWaterfallCompleteness_SumEqualsPayment() {
        Decimal payment = 123456.78;
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 500,
            'outstanding_Fee'       => 2000,
            'outstanding_Interest'  => 70000,
            'outstanding_Principal' => 60000
        };
        CalcContext ctx = buildCtx(outstanding);

        StandardWaterfallAllocator alloc = new StandardWaterfallAllocator();
        EngineResult result = alloc.allocate(payment, ctx, new List<Payment_Schedule__c>());

        Decimal sumAllocated = 0;
        for (SObject s : result.recordsToInsert) {
            sumAllocated += (Decimal) s.get('Amount__c');
        }
        // Total allocated + unallocated must equal payment
        Decimal unallocated = (Decimal) result.metadata.get('unallocated');
        Assert.areEqual(payment, sumAllocated + unallocated,
            'Spec invariant: sum(allocations) + unallocated = payment amount exactly');
    }

    // ── DefaultEventWaterfallAllocator — Spec order: Penalty → Interest → Fee → Principal ─

    @IsTest
    static void testDefaultEvent_AllocationOrder_PenaltyInterestFeePrincipal() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 1000,
            'outstanding_Interest'  => 50000,
            'outstanding_Fee'       => 5000,
            'outstanding_Principal' => 80000
        };
        CalcContext ctx = buildCtx(outstanding);

        DefaultEventWaterfallAllocator alloc = new DefaultEventWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.isTrue(result.success);
        List<String> components = allocationComponents(result);
        Assert.areEqual('Penalty',   components[0], 'DefaultEvent: Penalty first');
        Assert.areEqual('Interest',  components[1], 'DefaultEvent: Interest second');
        Assert.areEqual('Fee',       components[2], 'DefaultEvent: Fee third');
        Assert.areEqual('Principal', components[3], 'DefaultEvent: Principal last');
    }

    @IsTest
    static void testDefaultEvent_Amounts_Correct() {
        // 100K: Penalty 1K, Interest 50K, Fee 5K → leaves 44K for Principal (80K due)
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 1000,
            'outstanding_Interest'  => 50000,
            'outstanding_Fee'       => 5000,
            'outstanding_Principal' => 80000
        };
        CalcContext ctx = buildCtx(outstanding);
        DefaultEventWaterfallAllocator alloc = new DefaultEventWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.areEqual(1000,  allocationAmount(result, 'Penalty'));
        Assert.areEqual(50000, allocationAmount(result, 'Interest'));
        Assert.areEqual(5000,  allocationAmount(result, 'Fee'));
        Assert.areEqual(44000, allocationAmount(result, 'Principal'));
        Assert.areEqual(0, (Decimal) result.metadata.get('unallocated'), 'Nothing unallocated');
    }

    @IsTest
    static void testDefaultEvent_Execute_DelegatesToAllocate() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Interest'  => 20000,
            'outstanding_Principal' => 10000
        };
        CalcContext ctx = buildCtx(outstanding);
        ctx.extras.put('paymentAmount', 15000);

        DefaultEventWaterfallAllocator alloc = new DefaultEventWaterfallAllocator();
        Boolean threw = false;
        try { alloc.execute(ctx); } catch (Exception e) { threw = true; }
        Assert.isFalse(threw, 'DefaultEventWaterfallAllocator.execute must not throw');
    }

    // ── EnforcementWaterfallAllocator — Spec order: Penalty → Interest → Principal → Fee ─

    @IsTest
    static void testEnforcement_AllocationOrder_PenaltyInterestPrincipalFee() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 1000,
            'outstanding_Interest'  => 50000,
            'outstanding_Principal' => 40000,
            'outstanding_Fee'       => 5000
        };
        CalcContext ctx = buildCtx(outstanding);

        EnforcementWaterfallAllocator alloc = new EnforcementWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.isTrue(result.success);
        List<String> components = allocationComponents(result);
        Assert.areEqual('Penalty',   components[0], 'Enforcement: Penalty first');
        Assert.areEqual('Interest',  components[1], 'Enforcement: Interest second');
        Assert.areEqual('Principal', components[2], 'Enforcement: Principal third');
        Assert.areEqual('Fee',       components[3], 'Enforcement: Fee last');
    }

    @IsTest
    static void testEnforcement_Amounts_FullyAllocatedWithSurplus() {
        // 100K: Penalty 1K, Interest 50K, Principal 40K, Fee 5K — total dues = 96K → 4K surplus
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Penalty'   => 1000,
            'outstanding_Interest'  => 50000,
            'outstanding_Principal' => 40000,
            'outstanding_Fee'       => 5000
        };
        CalcContext ctx = buildCtx(outstanding);
        EnforcementWaterfallAllocator alloc = new EnforcementWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>());

        Assert.areEqual(1000,  allocationAmount(result, 'Penalty'));
        Assert.areEqual(50000, allocationAmount(result, 'Interest'));
        Assert.areEqual(40000, allocationAmount(result, 'Principal'));
        Assert.areEqual(5000,  allocationAmount(result, 'Fee'));
        Assert.areEqual(4000,  (Decimal) result.metadata.get('unallocated'), '4K unallocated after all dues covered');
    }

    @IsTest
    static void testEnforcement_Execute_DelegatesToAllocate() {
        Map<String,Object> outstanding = new Map<String,Object>{
            'outstanding_Principal' => 50000
        };
        CalcContext ctx = buildCtx(outstanding);
        ctx.extras.put('paymentAmount', 30000);

        EnforcementWaterfallAllocator alloc = new EnforcementWaterfallAllocator();
        Boolean threw = false;
        try { alloc.execute(ctx); } catch (Exception e) { threw = true; }
        Assert.isFalse(threw, 'EnforcementWaterfallAllocator.execute must not throw');
    }

    // ── DefaultEventWaterfallAllocator — with Payment_Schedule scheduleTargets ─

    @IsTest
    static void testDefaultEvent_WithScheduleTargets_AllocatesFromPS() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'DefEv Sched FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'DefEv Sched DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'DEVSCH001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(-1),
            Period_End__c     = Date.today(),
            Due_Date__c       = Date.today(),
            Principal_Due__c  = 50000,
            Interest_Due__c   = 30000,
            Fees_Due__c       = 5000,
            Net_Due__c        = 85000,
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'DEFEV-PS-SCH-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-defev-sched')
            .build();

        Test.startTest();
        DefaultEventWaterfallAllocator alloc = new DefaultEventWaterfallAllocator();
        EngineResult result = alloc.allocate(60000, ctx, new List<Payment_Schedule__c>{ ps });
        Test.stopTest();

        Assert.isTrue(result.success, 'DefaultEvent with schedule targets must succeed');
        Assert.isFalse(result.recordsToInsert.isEmpty(), 'Must have at least one allocation row');
        // Order: Penalty → Interest → Fee → Principal; Interest funded first from PS.Interest_Due__c
        List<String> components = allocationComponents(result);
        Assert.areEqual('Interest', components[0], 'DefaultEvent PS path: Interest funded first');
    }

    // ── EnforcementWaterfallAllocator — with Payment_Schedule scheduleTargets ─

    @IsTest
    static void testEnforcement_WithScheduleTargets_AllocatesFromPS() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Enf Sched FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Enf Sched DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'ENFSCH001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(-1),
            Period_End__c     = Date.today(),
            Due_Date__c       = Date.today(),
            Principal_Due__c  = 60000,
            Interest_Due__c   = 25000,
            Fees_Due__c       = 3000,
            Net_Due__c        = 88000,
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'ENFOR-PS-SCH-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-enf-sched')
            .build();

        Test.startTest();
        EnforcementWaterfallAllocator alloc = new EnforcementWaterfallAllocator();
        EngineResult result = alloc.allocate(50000, ctx, new List<Payment_Schedule__c>{ ps });
        Test.stopTest();

        Assert.isTrue(result.success, 'Enforcement with schedule targets must succeed');
        Assert.isFalse(result.recordsToInsert.isEmpty(), 'Must have at least one allocation row');
        // Order: Penalty → Interest → Principal → Fee; Interest funded first from PS.Interest_Due__c
        List<String> components = allocationComponents(result);
        Assert.areEqual('Interest', components[0], 'Enforcement PS path: Interest funded first');
    }

    // ── CashSweep — with Payment_Schedule scheduleTargets ────────────────────

    @IsTest
    static void testCashSweep_WithScheduleTargets_AllocatesFromScheduleFields() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'CashSweep Sched FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'CashSweep Sched DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'SWPSCH001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(-1),
            Period_End__c     = Date.today(),
            Due_Date__c       = Date.today(),
            Principal_Due__c  = 80000,
            Interest_Due__c   = 20000,
            Fees_Due__c       = 5000,
            Net_Due__c        = 105000,
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'SWEEP-PS-SCH-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        // When schedule targets are provided, outstandings are read from the PS fields
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-sweep-sched')
            .build();

        Test.startTest();
        CashSweepWaterfallAllocator alloc = new CashSweepWaterfallAllocator();
        EngineResult result = alloc.allocate(100000, ctx, new List<Payment_Schedule__c>{ ps });
        Test.stopTest();

        Assert.isTrue(result.success, 'CashSweep with schedule targets must succeed');
        Assert.isFalse(result.recordsToInsert.isEmpty(), 'Must have at least one allocation row');
    }
}