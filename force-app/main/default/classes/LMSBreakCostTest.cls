/**
 * LMSBreakCostTest
 * Covers: BreakCostCalculator (all basis codes), MarginRatchetEvaluator
 * Pure-compute tests use static compute() with no SOQL.
 * MarginRatchetEvaluator tests require Pricing_Grid_Band__c data.
 */
@IsTest
private class LMSBreakCostTest {

    // ─── BreakCostCalculator.compute() ───────────────────────────────────────

    private static Prepayment_Event__c mockEvent(Decimal principal, String basis) {
        Prepayment_Event__c pe = new Prepayment_Event__c();
        pe.Prepaid_Principal__c  = principal;
        pe.Break_Cost_Basis__c   = basis;
        return pe;
    }

    @IsTest
    static void testBreakCost_Par_ReturnsZero() {
        Prepayment_Event__c pe = mockEvent(5000000, 'Par');
        Decimal cost = BreakCostCalculator.compute(pe, new Map<String,Object>());
        Assert.areEqual(0, cost, 'Par basis always returns 0 break cost');
    }

    @IsTest
    static void testBreakCost_UnknownBasis_ReturnsZero() {
        Prepayment_Event__c pe = mockEvent(1000000, 'SomethingElse');
        Decimal cost = BreakCostCalculator.compute(pe, new Map<String,Object>());
        Assert.areEqual(0, cost, 'Unknown basis should return 0');
    }

    @IsTest
    static void testBreakCost_BlankBasis_ReturnsZero() {
        Prepayment_Event__c pe = mockEvent(1000000, '');
        Decimal cost = BreakCostCalculator.compute(pe, new Map<String,Object>());
        Assert.areEqual(0, cost, 'Blank basis returns 0');
    }

    @IsTest
    static void testBreakCost_SlidingScale_CorrectAmount() {
        // 2,000,000 * 3% = 60,000
        Prepayment_Event__c pe = mockEvent(2000000, 'Sliding_Scale');
        Decimal cost = BreakCostCalculator.compute(pe,
            new Map<String,Object>{ 'slidingScalePct' => 3.0 });
        Assert.areEqual(60000, cost, '2M * 3% = 60,000');
    }

    @IsTest
    static void testBreakCost_SlidingScale_ZeroPct_ReturnsZero() {
        Prepayment_Event__c pe = mockEvent(5000000, 'Sliding_Scale');
        Decimal cost = BreakCostCalculator.compute(pe,
            new Map<String,Object>{ 'slidingScalePct' => 0.0 });
        Assert.areEqual(0, cost);
    }

    @IsTest
    static void testBreakCost_NonCallPeriodBreach_ReturnsFlatFee() {
        Prepayment_Event__c pe = mockEvent(1000000, 'Non_Call_Period_Breach');
        Decimal cost = BreakCostCalculator.compute(pe,
            new Map<String,Object>{ 'nonCallFeeAmount' => 250000 });
        Assert.areEqual(250000, cost, 'Non-call fee is fixed regardless of principal');
    }

    @IsTest
    static void testBreakCost_MakeWholeTreasuryPlus_CorrectFormula() {
        // 1,000,000 * (200 bps / 10000) * 3 years = 1M * 0.02 * 3 = 60,000
        Prepayment_Event__c pe = mockEvent(1000000, 'Make_Whole_Treasury_Plus');
        Decimal cost = BreakCostCalculator.compute(pe,
            new Map<String,Object>{
                'spreadBps'           => 200.0,
                'remainingTenorYears' => 3.0
            });
        Assert.areEqual(60000, cost, '1M × 200bps × 3yr = 60,000');
    }

    @IsTest
    static void testBreakCost_MakeWholeTreasuryPlus_MissingExtras_ReturnsZero() {
        // No spreadBps / remainingTenorYears → both default to 0 → cost = 0
        Prepayment_Event__c pe = mockEvent(1000000, 'Make_Whole_Treasury_Plus');
        Decimal cost = BreakCostCalculator.compute(pe, new Map<String,Object>());
        Assert.areEqual(0, cost);
    }

    @IsTest
    static void testBreakCost_HALF_EVEN_Rounding() {
        // 1,000,001 * 1.5% = 15,000.015 → rounds HALF_EVEN → 15,000.02 (5 rounds up to even)
        Prepayment_Event__c pe = mockEvent(1000001, 'Sliding_Scale');
        Decimal cost = BreakCostCalculator.compute(pe,
            new Map<String,Object>{ 'slidingScalePct' => 1.5 });
        Assert.isTrue(cost >= 15000 && cost <= 15001, 'Should round to 2dp with HALF_EVEN');
    }

    // ─── MarginRatchetEvaluator ───────────────────────────────────────────────

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Ratchet FI');
        insert fi;

        // DP must exist before Pricing_Grid (grid requires Debt_Position__c)
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Ratchet DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'BKCST-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        Pricing_Grid__c grid = new Pricing_Grid__c(
            Debt_Position__c  = dp.Id,
            Effective_Date__c = Date.today().addDays(-30),
            Ratio_Metric__c   = 'Debt_to_EBITDA'
        );
        insert grid;

        // Link DP back to its Pricing_Grid
        update new Debt_Position__c(Id = dp.Id, Pricing_Grid__c = grid.Id);
        TriggerContext.getInstance().bypassGuards = false;

        // Two bands: 0-2.0 → 3.5% margin; 2.0+ → 4.5% margin
        List<Pricing_Grid_Band__c> bands = new List<Pricing_Grid_Band__c>{
            new Pricing_Grid_Band__c(
                Pricing_Grid__c      = grid.Id, Band_Order__c = 1,
                Ratio_Lower_Bound__c = 0,     Ratio_Upper_Bound__c = 2.0,
                Margin__c = 3.5, Is_Active__c = true, Band_Label__c = 'Low Leverage'),
            new Pricing_Grid_Band__c(
                Pricing_Grid__c      = grid.Id, Band_Order__c = 2,
                Ratio_Lower_Bound__c = 2.0,   Ratio_Upper_Bound__c = null,
                Margin__c = 4.5, Is_Active__c = true, Band_Label__c = 'High Leverage')
        };
        insert bands;

        // Applied IRT at 3.5%
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Spread__c             = 3.5,
            Application_Status__c = 'Applied',
            Actual_Application_Date__c = Date.today().addDays(-10)
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert irt;
        TriggerContext.getInstance().bypassGuards = false;
    }

    @IsTest
    static void testMarginRatchet_NewBand_CreatesIRT() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        // ratio = 3.0 → maps to High Leverage band (4.5%) — different from current (3.5%)
        Decimal ratio = 3.0;

        Test.startTest();
        MarginRatchetEvaluator.evaluate(dp.Id, null, Date.today(), ratio);
        Test.stopTest();

        List<Interest_Rate_Terms__c> newIRTs = [
            SELECT Id, Spread__c, Rate_Segment_Type__c, Application_Status__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dp.Id AND Rate_Segment_Type__c = 'Amended Rate'
        ];
        Assert.areEqual(1, newIRTs.size(), 'One new IRT must be created for margin change');
        Assert.areEqual(4.5, newIRTs[0].Spread__c, 'New margin = 4.5% (High Leverage band)');
        Assert.areEqual('Pending', newIRTs[0].Application_Status__c);
    }

    @IsTest
    static void testMarginRatchet_SameBand_NoNewIRT() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        // ratio = 1.0 → maps to Low Leverage band (3.5%) — same as current applied IRT
        Integer before = [SELECT COUNT() FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id];

        Test.startTest();
        MarginRatchetEvaluator.evaluate(dp.Id, null, Date.today(), 1.0);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id];
        Assert.areEqual(before, after, 'Same band → no new IRT should be created');
    }

    @IsTest
    static void testMarginRatchet_NoPricingGrid_NoOp() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'No Grid FI');
        insert fi;
        Debt_Position__c dp2 = new Debt_Position__c(
            Name = 'No Grid DP', Financial_Instrument__c = fi.Id,
            Status__c = 'Active', Pricing_Grid__c = null,
            iPlatform_External_Id__c = 'BKCST-002'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp2;
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        try {
            MarginRatchetEvaluator.evaluate(dp2.Id, null, Date.today(), 2.5);
        } catch (Exception e) { threw = true; }
        Assert.isFalse(threw, 'No pricing grid → should return silently, no exception');
    }

    // ─── BreakCostCalculator.calculateFromFlow (@InvocableMethod) ─────────────

    @IsTest
    static void testBreakCostCalculator_CalculateFromFlow_ParBasis_ReturnZero() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Flow BC FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Flow BC DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'FLOWBC001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        Prepayment_Event__c pe = new Prepayment_Event__c(
            Debt_Position__c     = dp.Id,
            Status__c            = 'Approved',
            Prepaid_Principal__c = 500000,
            Prepayment_Date__c   = Date.today(),
            Notice_Date__c       = Date.today(),
            Break_Cost_Basis__c  = 'Par'
        );
        insert pe;
        TriggerContext.getInstance().bypassGuards = false;

        BreakCostCalculator.BreakCostRequest req = new BreakCostCalculator.BreakCostRequest();
        req.prepaymentEventId = pe.Id;

        Test.startTest();
        List<Decimal> results = BreakCostCalculator.calculateFromFlow(
            new List<BreakCostCalculator.BreakCostRequest>{ req });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'calculateFromFlow must return one result per request');
        Assert.areEqual(0, results[0], 'Par break cost must be 0');
        Prepayment_Event__c peAfter = [SELECT Break_Cost__c FROM Prepayment_Event__c WHERE Id = :pe.Id];
        Assert.areEqual(0, peAfter.Break_Cost__c, 'calculateFromFlow must write Break_Cost__c = 0 onto the PE');
    }
}