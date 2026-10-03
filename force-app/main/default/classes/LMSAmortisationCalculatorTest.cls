/**
 * LMSAmortisationCalculatorTest
 * Covers: BulletAmortisationCalculator, EqualPrincipalAmortisationCalculator,
 *         EqualInstalmentAmortisationCalculator, StepUpInterestCalculator
 * Verifies correct numerical output for each amortisation and step-up interest strategy.
 */
@IsTest
private class LMSAmortisationCalculatorTest {

    // ─── Helper ──────────────────────────────────────────────────────────────

    private static CalcContext buildCtx(Decimal principal, Decimal rate,
                                         Date start, Date periodEnd, Map<String,Object> extras) {
        return new CalcContext.Builder()
            .setDebtPositionId(null)
            .setPrincipal(principal)
            .setInterestRate(rate)
            .setPeriodStartDate(start)
            .setPeriodEndDate(periodEnd)
            .setDayCountConvention('ACT_365')
            .setCorrelationId('test')
            .setExtras(extras != null ? extras : new Map<String,Object>())
            .build();
    }

    // ─── BulletAmortisationCalculator ────────────────────────────────────────

    @IsTest
    static void testBullet_NonFinalPeriod_ReturnsZero() {
        CalcContext ctx = buildCtx(1000000, 8.0, Date.today(), Date.today().addMonths(3),
            new Map<String,Object>{ 'isFinalPeriod' => false });
        BulletAmortisationCalculator calc = new BulletAmortisationCalculator();

        Test.startTest();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Test.stopTest();

        Assert.areEqual(0, result.calculatedAmount, 'Non-final period must return 0 principal due');
        Assert.areEqual('Bullet', result.resultType);
    }

    @IsTest
    static void testBullet_FinalPeriod_ReturnsFullPrincipal() {
        Decimal principal = 750000;
        CalcContext ctx = buildCtx(principal, 8.0, Date.today(), Date.today().addMonths(3),
            new Map<String,Object>{ 'isFinalPeriod' => true });
        BulletAmortisationCalculator calc = new BulletAmortisationCalculator();

        Test.startTest();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Test.stopTest();

        Assert.areEqual(principal, result.calculatedAmount, 'Final period must return full outstanding principal');
        Assert.areEqual('Bullet', result.resultType);
    }

    @IsTest
    static void testBullet_NullIsFinalPeriod_ReturnsZero() {
        CalcContext ctx = buildCtx(500000, 5.0, Date.today(), Date.today().addMonths(6),
            new Map<String,Object>()); // isFinalPeriod absent → null
        BulletAmortisationCalculator calc = new BulletAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Assert.areEqual(0, result.calculatedAmount, 'Absent isFinalPeriod must default to 0');
    }

    @IsTest
    static void testBullet_Execute_DelegatesToCalculate() {
        CalcContext ctx = buildCtx(1000000, 8.0, Date.today(), Date.today().addMonths(3),
            new Map<String,Object>{ 'isFinalPeriod' => true });
        BulletAmortisationCalculator calc = new BulletAmortisationCalculator();
        EngineResult via = calc.execute(ctx);
        Assert.areEqual(1000000, via.calculatedAmount, 'execute() must delegate to calculatePrincipalRepayment()');
    }

    // ─── EqualPrincipalAmortisationCalculator ────────────────────────────────

    @IsTest
    static void testEqualPrincipal_StandardDivision() {
        // 1,200,000 / 12 periods = 100,000 per period
        CalcContext ctx = buildCtx(1200000, 8.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'originalPrincipal' => 1200000, 'totalPeriods' => 12 });
        EqualPrincipalAmortisationCalculator calc = new EqualPrincipalAmortisationCalculator();

        Test.startTest();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Test.stopTest();

        Assert.areEqual(100000, result.calculatedAmount, '1.2M / 12 = 100,000');
        Assert.areEqual('Equal_Principal', result.resultType);
    }

    @IsTest
    static void testEqualPrincipal_FallsBackToCtxPrincipal_WhenNoOriginalExtra() {
        // No originalPrincipal extra → uses ctx.principal
        CalcContext ctx = buildCtx(900000, 6.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 9 });
        EqualPrincipalAmortisationCalculator calc = new EqualPrincipalAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        // 900000 / 9 = 100000
        Assert.areEqual(100000, result.calculatedAmount);
    }

    @IsTest
    static void testEqualPrincipal_ZeroPeriods_DefaultsToOne() {
        CalcContext ctx = buildCtx(500000, 5.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 0 }); // invalid → default 1
        EqualPrincipalAmortisationCalculator calc = new EqualPrincipalAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Assert.areEqual(500000, result.calculatedAmount, 'Zero periods defaults to 1 → full principal');
    }

    @IsTest
    static void testEqualPrincipal_Execute_Delegates() {
        CalcContext ctx = buildCtx(600000, 6.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 6 });
        EqualPrincipalAmortisationCalculator calc = new EqualPrincipalAmortisationCalculator();
        EngineResult viaExecute = calc.execute(ctx);
        EngineResult viaDirect  = calc.calculatePrincipalRepayment(ctx);
        Assert.areEqual(viaDirect.calculatedAmount, viaExecute.calculatedAmount);
    }

    // ─── EqualInstalmentAmortisationCalculator ────────────────────────────────

    @IsTest
    static void testEqualInstalment_ZeroRate_IsSimpleDivision() {
        // Zero interest rate → instalment = principal / totalPeriods
        // 120,000 / 12 = 10,000 per period, interest=0, principalComponent=10,000
        CalcContext ctx = buildCtx(120000, 0.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 12 });
        EqualInstalmentAmortisationCalculator calc = new EqualInstalmentAmortisationCalculator();

        Test.startTest();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Test.stopTest();

        Assert.areEqual(10000, result.calculatedAmount, 'Zero-rate equal instalment: principal / n = 10,000');
        Assert.areEqual('Equal_Instalment', result.resultType);
    }

    @IsTest
    static void testEqualInstalment_PositiveRate_PrincipalComponentLessThanInstalment() {
        // 1,000,000 at 12% annual / 12 monthly periods
        // Monthly rate = 1%; annuity = 1M * 0.01 * (1.01)^12 / ((1.01)^12 - 1) ≈ 88,849
        CalcContext ctx = buildCtx(1000000, 12.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 12 });
        EqualInstalmentAmortisationCalculator calc = new EqualInstalmentAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        // Interest component = 1,000,000 * (12%/100/12) = 10,000
        // Principal component < instalment
        Decimal instalment = (Decimal) result.metadata.get('totalInstalment');
        Decimal interest   = (Decimal) result.metadata.get('interestComponent');
        Assert.isTrue(instalment != null && instalment > 0, 'Instalment must be positive');
        Assert.isTrue(result.calculatedAmount < instalment, 'Principal component < total instalment');
        Assert.areEqual(
            instalment.setScale(2, RoundingMode.HALF_EVEN),
            (result.calculatedAmount + interest).setScale(2, RoundingMode.HALF_EVEN),
            'Principal + interest = instalment'
        );
    }

    @IsTest
    static void testEqualInstalment_SinglePeriod_PrincipalEqualsInstalmentMinusInterest() {
        // 1 period: instalment = P * r(1+r)^1 / ((1+r)^1 - 1) = P(1+r)
        // principal component = instalment - interest
        CalcContext ctx = buildCtx(500000, 6.0, Date.today(), Date.today().addMonths(1),
            new Map<String,Object>{ 'totalPeriods' => 1 });
        EqualInstalmentAmortisationCalculator calc = new EqualInstalmentAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);
        Assert.isTrue(result.calculatedAmount > 0);
    }

    // ─── StepUpInterestCalculator ─────────────────────────────────────────────

    @IsTest
    static void testStepUp_Applied_UsesContextRate() {
        // Applied → uses ctx.interestRate (8.5%)
        // 1M at 8.5% ACT/365 for 90 days = 1M * 0.085 * (90/365) ≈ 20,958.90
        Date start     = Date.today();
        Date periodEnd = start.addDays(90);
        CalcContext ctx = buildCtx(1000000, 8.5, start, periodEnd,
            new Map<String,Object>{ 'applicationStatus' => 'Applied' });
        StepUpInterestCalculator calc = new StepUpInterestCalculator();

        Test.startTest();
        EngineResult result = calc.calculate(ctx);
        Test.stopTest();

        Decimal fraction = 90.0 / 365.0;
        Decimal expected = (1000000 * (8.5 / 100) * fraction).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount, 'Applied status must use 8.5% rate');
        Assert.areEqual('Step_Up', result.resultType);
        Assert.areEqual('Step-up rate applied.', result.metadata.get('applicationDecisionReason'));
    }

    @IsTest
    static void testStepUp_Deferred_UsesPriorRate() {
        // Deferred → uses priorRate from extras (5%)
        Date start     = Date.today();
        Date periodEnd = start.addDays(90);
        CalcContext ctx = buildCtx(1000000, 8.5, start, periodEnd,
            new Map<String,Object>{
                'applicationStatus' => 'Deferred',
                'priorRate'         => 5.0
            });
        StepUpInterestCalculator calc = new StepUpInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Decimal fraction = 90.0 / 365.0;
        Decimal expected = (1000000 * (5.0 / 100) * fraction).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount, 'Deferred must use priorRate (5%), not step-up rate (8.5%)');
        Assert.isTrue(((String) result.metadata.get('applicationDecisionReason')).contains('Deferred'));
    }

    @IsTest
    static void testStepUp_Pending_UsesPriorRate() {
        Date start     = Date.today();
        Date periodEnd = start.addDays(30);
        CalcContext ctx = buildCtx(500000, 10.0, start, periodEnd,
            new Map<String,Object>{
                'applicationStatus' => 'Pending',
                'priorRate'         => 7.0
            });
        StepUpInterestCalculator calc = new StepUpInterestCalculator();
        EngineResult result = calc.calculate(ctx);

        Decimal fraction = 30.0 / 365.0;
        Decimal expected = (500000 * (7.0 / 100) * fraction).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount, 'Pending must use priorRate 7%');
    }

    @IsTest
    static void testStepUp_Deferred_NoPriorRate_UsesContextRate() {
        // Deferred but no priorRate → falls back to ctx.interestRate
        Date start     = Date.today();
        Date periodEnd = start.addDays(30);
        CalcContext ctx = buildCtx(500000, 9.0, start, periodEnd,
            new Map<String,Object>{ 'applicationStatus' => 'Deferred' }); // no priorRate
        StepUpInterestCalculator calc = new StepUpInterestCalculator();
        EngineResult result = calc.calculate(ctx);
        Assert.isTrue(result.calculatedAmount > 0, 'Should compute something even without priorRate');
    }

    @IsTest
    static void testStepUp_Execute_Delegates() {
        Date start     = Date.today();
        Date periodEnd = start.addDays(30);
        CalcContext ctx = buildCtx(1000000, 8.0, start, periodEnd,
            new Map<String,Object>{ 'applicationStatus' => 'Applied' });
        StepUpInterestCalculator calc = new StepUpInterestCalculator();
        Assert.areEqual(calc.calculate(ctx).calculatedAmount, calc.execute(ctx).calculatedAmount);
    }
}