/**
 * LMSSculptedAmortisationTest
 * Verifies SculptedAmortisationCalculator matches on Period_Start__c and reads
 * Repayment_Amount__c correctly. Spec v3 Part 4.6.
 */
@IsTest
private class LMSSculptedAmortisationTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
    }

    // Happy path: period matches, amount returned.
    // Period_Start__c = 2026-03-01, Repayment_Amount = 50,000
    @IsTest
    static void testSculpted_MatchesByPeriodStart_ReturnsAmount() {
        Date periodStart = Date.newInstance(2026, 3, 1);

        Principal_Repayment_Schedules__c prs = new Principal_Repayment_Schedules__c(
            Period_Start__c      = periodStart,
            Repayment_Amount__c  = 50000
        );
        // Build CalcContext with the sculpted schedule in extras
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000)
            .setInterestRate(8.0)
            .setDayCountConvention('ACT_365')
            .setPeriodStartDate(periodStart)
            .setPeriodEndDate(Date.newInstance(2026, 3, 31))
            .setCorrelationId('sculpt-match')
            .setExtras(new Map<String,Object>{
                'sculptedSchedule' => new List<Principal_Repayment_Schedules__c>{ prs }
            })
            .build();

        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        Assert.isTrue(result.success, 'Should succeed when period matches');
        Assert.areEqual(50000.00, result.calculatedAmount,
            'Must return Repayment_Amount__c value, not 0 placeholder');
        Assert.areEqual('Sculpted', result.resultType);
    }

    // No matching period → amount should be 0 (no match found, loop exits without setting due)
    @IsTest
    static void testSculpted_NoMatch_ReturnsZero() {
        Date periodStart = Date.newInstance(2026, 3, 1);
        Date otherStart  = Date.newInstance(2026, 4, 1); // different

        Principal_Repayment_Schedules__c prs = new Principal_Repayment_Schedules__c(
            Period_Start__c     = otherStart,
            Repayment_Amount__c = 50000
        );
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setPeriodStartDate(periodStart)
            .setCorrelationId('sculpt-nomatch')
            .setExtras(new Map<String,Object>{
                'sculptedSchedule' => new List<Principal_Repayment_Schedules__c>{ prs }
            })
            .build();

        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        Assert.areEqual(0, result.calculatedAmount,
            'No matching period should produce 0 repayment amount');
    }

    // Null schedule → fallback to bullet (isFinalPeriod = false → 0)
    @IsTest
    static void testSculpted_NullSchedule_FallsBackToBullet_NonFinal() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setCorrelationId('sculpt-null')
            .setExtras(new Map<String,Object>{ 'isFinalPeriod' => false })
            .build();

        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        Assert.areEqual(0, result.calculatedAmount, 'Non-final period with no schedule = 0');
        Assert.areEqual('Sculpted_Fallback_Bullet', result.resultType);
    }

    // Null schedule → fallback to bullet (isFinalPeriod = true → full principal)
    @IsTest
    static void testSculpted_NullSchedule_FallsBackToBullet_Final() {
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setCorrelationId('sculpt-final')
            .setExtras(new Map<String,Object>{ 'isFinalPeriod' => true })
            .build();

        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        Assert.areEqual(500000, result.calculatedAmount,
            'Final period fallback = full principal');
    }

    // Multiple rows: correct row selected by period start
    @IsTest
    static void testSculpted_MultipleRows_CorrectRowSelected() {
        Date march = Date.newInstance(2026, 3, 1);
        Date april = Date.newInstance(2026, 4, 1);

        Principal_Repayment_Schedules__c row1 = new Principal_Repayment_Schedules__c(
            Period_Start__c = march, Repayment_Amount__c = 100000);
        Principal_Repayment_Schedules__c row2 = new Principal_Repayment_Schedules__c(
            Period_Start__c = april, Repayment_Amount__c = 200000);

        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(500000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setPeriodStartDate(april)
            .setCorrelationId('sculpt-multi')
            .setExtras(new Map<String,Object>{
                'sculptedSchedule' => new List<Principal_Repayment_Schedules__c>{ row1, row2 }
            })
            .build();

        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        EngineResult result = calc.calculatePrincipalRepayment(ctx);

        Assert.areEqual(200000, result.calculatedAmount,
            'Must select April row (200k), not March row (100k)');
    }

    // execute() delegates to calculatePrincipalRepayment
    @IsTest
    static void testExecute_DelegatesToCalculatePrincipalRepayment() {
        Date periodStart = Date.newInstance(2026, 5, 1);
        Principal_Repayment_Schedules__c prs = new Principal_Repayment_Schedules__c(
            Period_Start__c = periodStart, Repayment_Amount__c = 75000);
        CalcContext ctx = new CalcContext.Builder()
            .setPrincipal(750000).setInterestRate(8.0).setDayCountConvention('ACT_365')
            .setPeriodStartDate(periodStart)
            .setCorrelationId('sculpt-exec')
            .setExtras(new Map<String,Object>{
                'sculptedSchedule' => new List<Principal_Repayment_Schedules__c>{ prs }
            })
            .build();
        SculptedAmortisationCalculator calc = new SculptedAmortisationCalculator();
        Assert.areEqual(75000, calc.execute(ctx).calculatedAmount);
    }
}