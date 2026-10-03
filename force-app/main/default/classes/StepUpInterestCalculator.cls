/**
 * StepUpInterestCalculator — implements IInterestCalculator
 * Step-up rate: checks Application_Status on Interest_Rate_Terms.
 * If Applied: uses new (stepped-up) rate from context.
 * If Pending/Deferred: uses prior rate stored in context extras.
 * Records Application_Decision_Reason on Interest_Period for audit.
 */
public class StepUpInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public StepUpInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();
        String appStatus = (String) ctx.extras.get('applicationStatus');
        Decimal effectiveRate = ctx.interestRate;
        String decisionReason = 'Step-up rate applied.';

        if (appStatus == 'Deferred' || appStatus == 'Pending') {
            Object priorRate = ctx.extras.get('priorRate');
            if (priorRate != null) {
                effectiveRate = (Decimal) priorRate;
                decisionReason = 'Step-up deferred — prior rate used. Application status: ' + appStatus;
            }
        }

        IDayCountCalculator dcCalc = new GenericDayCountCalculator();
        Decimal fraction = dcCalc.getDayCountFraction(ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
        Decimal accrual = ctx.principal * (effectiveRate / 100) * fraction;
        result.setAmount(accrual.setScale(2, RoundingMode.HALF_EVEN));
        result.setResultType('Step_Up');
        result.putMeta('applicationDecisionReason', decisionReason);
        result.putMeta('effectiveRate', effectiveRate);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }
}