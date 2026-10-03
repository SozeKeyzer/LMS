/**
 * LMSCompoundingCalculatorTest
 * Correctness tests for CompoundingInterestCalculator and DefaultInterestCalculator.
 * All expected values derived analytically from spec Part 4.7 and Part 8.6.
 *
 * Rate convention: interestRate stored as percentage (e.g. 8.0 = 8%), consistent
 * with FixedRateInterestCalculator and spec Part 3.4 worked examples.
 */
@IsTest
private class LMSCompoundingCalculatorTest {

    // ── CompoundingInterestCalculator ─────────────────────────────────────────

    // Discrete compounding, no prior accrual (day 1).
    // 1,000,000 × (8.0/100) × (1/365) = 219.178... → 219.18 HALF_EVEN
    @IsTest
    static void testDiscreteCompounding_NoPriorAccrual() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(8.0)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 1, 1))
            .setPeriodEndDate(Date.newInstance(2026, 1, 31))
            .setCorrelationId('test-compound-d1')
            .setExtras(new Map<String,Object>{
                'compoundingFrequency'           => 'Monthly',
                'compoundingMethod'              => 'Discrete',
                'accruedThisCompoundingPeriod'   => 0
            })
            .build();

        CompoundingInterestCalculator calc = new CompoundingInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'Discrete compounding day 1 should succeed');
        Decimal expected = (1000000 * 0.08 * (1.0/365.0)).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount,
            'Discrete day 1: 1M × 8% × 1/365 ≈ 219.18');
        Assert.isTrue(result.resultType.startsWith('Compounding_Discrete'),
            'ResultType should indicate Discrete');
    }

    // Day 2: basis grows because previous day's accrual is included.
    // basis = 1,000,000 + 219.18 = 1,000,219.18
    // accrued = 1,000,219.18 × 0.08 × (1/365) = 219.23 (HALF_EVEN)
    @IsTest
    static void testDiscreteCompounding_WithPriorAccrual() {
        Decimal priorAccrual = (1000000 * 0.08 / 365.0).setScale(2, RoundingMode.HALF_EVEN);
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(8.0)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 1, 1))
            .setPeriodEndDate(Date.newInstance(2026, 1, 31))
            .setCorrelationId('test-compound-d2')
            .setExtras(new Map<String,Object>{
                'compoundingFrequency'           => 'Monthly',
                'compoundingMethod'              => 'Discrete',
                'accruedThisCompoundingPeriod'   => priorAccrual
            })
            .build();

        CompoundingInterestCalculator calc = new CompoundingInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Decimal basis = 1000000 + priorAccrual;
        Decimal expected = (basis * 0.08 / 365.0).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount,
            'Discrete day 2: basis should include prior day accrual');
        Assert.isTrue(result.calculatedAmount > 219.18,
            'Day 2 accrual must exceed day 1 (compounding effect)');
    }

    // Continuous compounding: e^(R×t) − 1 spread over period days.
    // Principal=1M, rate=8%, period=31 days (Jan 1→31)
    // tFull = 31/365; fullInterest = 1M × (e^(0.08×31/365) − 1); daily = fullInterest/31
    @IsTest
    static void testContinuousCompounding_ProrationCheck() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(8.0)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 1, 1))
            .setPeriodEndDate(Date.newInstance(2026, 1, 31))
            .setCalculationDate(Date.newInstance(2026, 1, 15))
            .setCorrelationId('test-compound-cont')
            .setExtras(new Map<String,Object>{
                'compoundingFrequency' => 'Monthly',
                'compoundingMethod'    => 'ACT_Continuous'
            })
            .build();

        CompoundingInterestCalculator calc = new CompoundingInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'Continuous compounding should succeed');
        // Must be positive and roughly consistent with simple daily (219 range)
        Assert.isTrue(result.calculatedAmount > 200 && result.calculatedAmount < 250,
            'Continuous daily accrual should be in the same range as simple (200–250 for 1M at 8%)');
        Assert.isTrue(result.resultType.contains('ACT_Continuous'),
            'ResultType should indicate ACT_Continuous');
    }

    // Continuous: should be slightly higher than discrete (compounding effect)
    @IsTest
    static void testContinuous_YieldsMoreThanDiscrete() {
        Map<String,Object> extrasDiscrete = new Map<String,Object>{
            'compoundingFrequency' => 'Monthly', 'compoundingMethod' => 'Discrete', 'accruedThisCompoundingPeriod' => 0
        };
        Map<String,Object> extrasContinuous = new Map<String,Object>{
            'compoundingFrequency' => 'Monthly', 'compoundingMethod' => 'ACT_Continuous'
        };

        CalcContext ctxD = new CalcContext.Builder()
            .setPrincipal(1000000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 1, 1)).setPeriodEndDate(Date.newInstance(2026, 1, 31))
            .setCalculationDate(Date.newInstance(2026, 1, 15))
            .setCorrelationId('d').setExtras(extrasDiscrete).build();
        CalcContext ctxC = new CalcContext.Builder()
            .setPrincipal(1000000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 1, 1)).setPeriodEndDate(Date.newInstance(2026, 1, 31))
            .setCalculationDate(Date.newInstance(2026, 1, 15))
            .setCorrelationId('c').setExtras(extrasContinuous).build();

        CompoundingInterestCalculator calc = new CompoundingInterestCalculator();
        Decimal discrete   = calc.calculate(ctxD).calculatedAmount;
        Decimal continuous = calc.calculate(ctxC).calculatedAmount;
        Assert.isTrue(continuous >= discrete,
            'Continuous compounding should yield >= discrete for same principal/rate');
    }

    // Error path: missing rate
    @IsTest
    static void testCompounding_MissingRate_ReturnsError() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setCorrelationId('missing-rate')
            .build();
        CompoundingInterestCalculator calc = new CompoundingInterestCalculator();
        EngineResult result = calc.calculate(ctx);
        Assert.isFalse(result.success, 'Missing rate should produce failure');
    }

    // freqPerYear helper
    @IsTest
    static void testFreqPerYear_AllValues() {
        Assert.areEqual(365, CompoundingInterestCalculator.freqPerYear('Daily'));
        Assert.areEqual(12,  CompoundingInterestCalculator.freqPerYear('Monthly'));
        Assert.areEqual(4,   CompoundingInterestCalculator.freqPerYear('Quarterly'));
        Assert.areEqual(1,   CompoundingInterestCalculator.freqPerYear('None'));
        Assert.areEqual(1,   CompoundingInterestCalculator.freqPerYear(null));
    }

    // ── DefaultInterestCalculator ─────────────────────────────────────────────

    // Simple default interest (no IoI): 500,000 × 12% × 1/365 = 164.38
    @IsTest
    static void testDefaultInterest_Simple() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000)
            .setInterestRate(12.0)
            .setDayCountConvention('ACT_365')
            .setCorrelationId('test-default-simple')
            .setExtras(new Map<String,Object>{
                'defaultInterestCompounding' => false,
                'compoundingFrequency'       => 'None',
                'unpaidAccruedInterest'      => 0
            })
            .build();

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Decimal expected = (500000 * 0.12 / 365.0).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount,
            'Simple default interest: 500k × 12% × 1/365 ≈ 164.38');
        Assert.isTrue(result.resultType.contains('Simple'));
    }

    // IoI (R20): basis = principal + unpaid accrued. 500k + 10k = 510k
    // 510,000 × 12% × 1/365 = 167.67 (HALF_EVEN)
    @IsTest
    static void testDefaultInterest_IoI_BasisIncludesUnpaidAccrued() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000)
            .setInterestRate(12.0)
            .setDayCountConvention('ACT_365')
            .setCorrelationId('test-default-ioi')
            .setExtras(new Map<String,Object>{
                'defaultInterestCompounding' => true,
                'compoundingFrequency'       => 'Daily',
                'unpaidAccruedInterest'      => 10000
            })
            .build();

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Decimal expectedSimple = (500000 * 0.12 / 365.0).setScale(2, RoundingMode.HALF_EVEN);
        Decimal expectedIoI    = (510000 * 0.12 / 365.0).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expectedIoI, result.calculatedAmount,
            'IoI basis must include 10,000 unpaid accrued');
        Assert.isTrue(result.calculatedAmount > expectedSimple,
            'IoI accrual must exceed simple (interest-on-interest growth)');
        Assert.isTrue(result.resultType.contains('IoI'));
    }

    // IoI with zero unpaidAccrued = same as simple
    @IsTest
    static void testDefaultInterest_IoI_ZeroUnpaidEqualsSimple() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(12.0).setDayCountConvention('ACT_365')
            .setCorrelationId('test-default-ioi-zero')
            .setExtras(new Map<String,Object>{
                'defaultInterestCompounding' => true, 'compoundingFrequency' => 'Daily', 'unpaidAccruedInterest' => 0
            }).build();
        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult r1 = calc.calculate(ctx);

        CalcContext ctx2 = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(12.0).setDayCountConvention('ACT_365')
            .setCorrelationId('test-default-simple2')
            .setExtras(new Map<String,Object>{
                'defaultInterestCompounding' => false, 'compoundingFrequency' => 'None', 'unpaidAccruedInterest' => 0
            }).build();
        EngineResult r2 = calc.calculate(ctx2);

        Assert.areEqual(r2.calculatedAmount, r1.calculatedAmount,
            'IoI with zero unpaid should equal simple interest');
    }

    // Error path: missing required fields
    @IsTest
    static void testDefaultInterest_MissingFields_ReturnsError() {
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('missing').build();
        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        Assert.isFalse(calc.calculate(ctx).success, 'Missing principal/rate should fail');
    }

    // ACT_360 vs ACT_365 gives larger fraction for ACT_360 (360 denominator < 365)
    @IsTest
    static void testDefaultInterest_ACT360_VsACT365() {
        CalcContext ctx360 = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(12.0).setDayCountConvention('ACT_360')
            .setCorrelationId('360').build();
        CalcContext ctx365 = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(12.0).setDayCountConvention('ACT_365')
            .setCorrelationId('365').build();
        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        Decimal r360 = calc.calculate(ctx360).calculatedAmount;
        Decimal r365 = calc.calculate(ctx365).calculatedAmount;
        Assert.isTrue(r360 > r365, 'ACT/360 produces larger daily accrual than ACT/365 (smaller denominator)');
    }
}