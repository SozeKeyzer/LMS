/**
 * LMSInterestCalculatorTest
 * Phase 3 spec compliance tests for interest calculation strategies.
 * Spec Part 3.4 worked example: 5M × 8.5% × ACT/365 (Mar 31→Jun 30 2026) = 105,958.90
 * Spec Part 12.1: currency amounts use HALF_EVEN (Banker's rounding).
 */
@IsTest
private class LMSInterestCalculatorTest {

    // Spec Part 3.4 worked example.
    // FixedRateInterestCalculator: 5,000,000 × (8.5/100) × (91/365) = 105,958.90
    @IsTest
    static void testFixedRate_SpecPart34() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(5000000)
            .setInterestRate(8.5)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 3, 31))
            .setPeriodEndDate(Date.newInstance(2026, 6, 30))
            .setCorrelationId('test-fixed-rate')
            .build();

        FixedRateInterestCalculator calc = new FixedRateInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'Calculation should succeed');
        Assert.areEqual(105958.90, result.calculatedAmount,
            'Spec Part 3.4: 5M × 8.5% × 91/365 = 105,958.90');
        Assert.areEqual('Fixed_Rate', result.resultType);
    }

    // FloatingRateInterestCalculator uses the same formula — same result.
    @IsTest
    static void testFloatingRate_SameFormulaAsFixed() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(5000000)
            .setInterestRate(8.5)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 3, 31))
            .setPeriodEndDate(Date.newInstance(2026, 6, 30))
            .setCorrelationId('test-floating-rate')
            .build();

        FloatingRateInterestCalculator calc = new FloatingRateInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Assert.areEqual(105958.90, result.calculatedAmount,
            'FloatingRate same formula: 5M × 8.5% × 91/365 = 105,958.90');
        Assert.areEqual('Floating_Rate', result.resultType);
    }

    // PIKInterestCalculator: same formula + isPIK = true in metadata.
    @IsTest
    static void testPIK_SetsIsPIKFlag() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(5000000)
            .setInterestRate(8.5)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 3, 31))
            .setPeriodEndDate(Date.newInstance(2026, 6, 30))
            .setCorrelationId('test-pik')
            .build();

        PIKInterestCalculator calc = new PIKInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Assert.areEqual(105958.90, result.calculatedAmount, 'PIK interest = same formula');
        Assert.areEqual(true, result.metadata.get('isPIK'), 'PIK calculator must set isPIK=true');
    }

    // PIKToggleInterestCalculator: 50% PIK / 50% cash split.
    // Total = 105,958.90; pikAmount = 52,979.45; cashAmount = 52,979.45
    @IsTest
    static void testPIKToggle_50PctSplit() {
        Map<String,Object> extras = new Map<String,Object>{ 'pikPercentage' => 50.0 };
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(5000000)
            .setInterestRate(8.5)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(Date.newInstance(2026, 3, 31))
            .setPeriodEndDate(Date.newInstance(2026, 6, 30))
            .setCorrelationId('test-piktop')
            .setExtras(extras)
            .build();

        PIKToggleInterestCalculator calc = new PIKToggleInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success);
        Decimal totalAccrual = 105958.90;
        Decimal halfEvenHalf = (totalAccrual * 50 / 100).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(halfEvenHalf, result.calculatedAmount,
            'Cash portion = 50% of total, HALF_EVEN');
        Assert.areEqual(halfEvenHalf, (Decimal) result.metadata.get('pikAmount'),
            'PIK portion = 50% of total, HALF_EVEN');
        Assert.areEqual(true, result.metadata.get('isPIKSplit'));
    }

    // Spec Part 12.1: currency uses HALF_EVEN (Banker's rounding).
    // 2.5 rounds to 2 (even) under HALF_EVEN, rounds to 3 under HALF_UP.
    @IsTest
    static void testHalfEvenRounding_BankersRoundingBehavior() {
        // Verify the Apex rounding modes behave as expected per spec Part 12.1
        Decimal half = 2.5;
        Assert.areEqual(2, (Integer) half.setScale(0, RoundingMode.HALF_EVEN),
            'HALF_EVEN: 2.5 rounds to even 2 (Banker\'s rounding)');
        Assert.areEqual(3, (Integer) half.setScale(0, RoundingMode.HALF_UP),
            'HALF_UP: 2.5 rounds to 3 (away-from-zero)');

        Decimal threeHalf = 3.5;
        Assert.areEqual(4, (Integer) threeHalf.setScale(0, RoundingMode.HALF_EVEN),
            'HALF_EVEN: 3.5 rounds to even 4');
        Assert.areEqual(4, (Integer) threeHalf.setScale(0, RoundingMode.HALF_UP),
            'HALF_UP: 3.5 also rounds to 4');

        // At 2dp: 2.225 — HALF_EVEN rounds to 2.22 (even 2); HALF_UP rounds to 2.23
        Decimal twoDP = 2.225;
        Assert.areEqual(2.22, twoDP.setScale(2, RoundingMode.HALF_EVEN),
            'HALF_EVEN: 2.225 → 2.22 (even digit)');
        Assert.areEqual(2.23, twoDP.setScale(2, RoundingMode.HALF_UP),
            'HALF_UP: 2.225 → 2.23');
    }

    // Error path: missing required context fields returns success=false.
    @IsTest
    static void testFixedRate_MissingContextReturnsError() {
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('test-bad-ctx')
            .build(); // No principal, rate, or convention

        FixedRateInterestCalculator calc = new FixedRateInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isFalse(result.success, 'Missing fields should return success=false');
        Assert.isTrue(String.isNotBlank(result.message), 'Error message should be populated');
    }

    // ─── DefaultInterestCalculator ────────────────────────────────────────────

    @IsTest
    static void testDefaultInterest_SimpleACT365_ComputesDailyAccrual() {
        // 1M × 10% × 1/365 = 273.97
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(10.0)
            .setDayCountConvention('ACT_365')
            .setCorrelationId('di-simple-365')
            .build();

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'Simple ACT_365 default interest must succeed');
        Decimal expected = (1000000 * (10.0 / 100) * (Decimal)1 / 365)
            .setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount,
            'DefaultInterest_Simple ACT_365: 1M × 10% × 1/365');
        Assert.isTrue(result.resultType.startsWith('DefaultInterest_Simple'),
            'resultType must start with DefaultInterest_Simple');
    }

    @IsTest
    static void testDefaultInterest_WithIoI_ExpandsBasis() {
        // basis = 1M + 50K = 1.05M; 1.05M × 10% × 1/365 = 287.67
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(10.0)
            .setDayCountConvention('ACT_365')
            .setExtras(new Map<String,Object>{
                'defaultInterestCompounding' => true,
                'compoundingFrequency'       => 'Monthly',
                'unpaidAccruedInterest'      => 50000
            })
            .setCorrelationId('di-ioi-365')
            .build();

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'IoI mode must succeed');
        Decimal expected = (1050000 * (10.0 / 100) * (Decimal)1 / 365)
            .setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount, 'IoI basis expands to 1.05M');
        Assert.isTrue(result.resultType.contains('IoI'), 'resultType must contain IoI when compounding');
    }

    @IsTest
    static void testDefaultInterest_ACT360_UsesThreeSixtyDenominator() {
        // 1M × 10% × 1/360 = 277.78
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(1000000)
            .setInterestRate(10.0)
            .setDayCountConvention('ACT_360')
            .setCorrelationId('di-360')
            .build();

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isTrue(result.success, 'ACT_360 must succeed');
        Decimal expected = (1000000 * (10.0 / 100) * (Decimal)1 / 360)
            .setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount, 'ACT_360 uses 360-day year');
    }

    @IsTest
    static void testDefaultInterest_MissingFields_ReturnsFailure() {
        CalcContext ctx = new CalcContext.Builder()
            .setCorrelationId('di-missing')
            .build(); // No principal or rate

        DefaultInterestCalculator calc = new DefaultInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Assert.isFalse(result.success, 'Missing interestRate and principal must return success=false');
    }

    @IsTest
    static void testQueryUnpaidAccruedInterest_NoRecords_ReturnsZero() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'UAI FI', Status__c = 'Active');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'UAI DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'UAI-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Decimal unpaid = DefaultInterestCalculator.queryUnpaidAccruedInterest(dp.Id, Date.today());
        Test.stopTest();

        Assert.areEqual(0, unpaid, 'queryUnpaidAccruedInterest with no Accrual_Daily__c records must return 0');
    }
}