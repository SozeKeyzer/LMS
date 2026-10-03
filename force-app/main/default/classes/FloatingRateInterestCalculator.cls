/**
 * FloatingRateInterestCalculator — implements IInterestCalculator
 * For floating-rate tranches (BBSW + margin).
 * Rate sourced from Interest_Period.All_In_Rate__c (index + margin, floor/ceiling applied by engine at period creation).
 * CalcContext.interestRate must be the all-in rate from the Interest_Period, not raw IRT.
 */
public class FloatingRateInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public FloatingRateInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();
        if (ctx.principal == null || ctx.interestRate == null) {
            result.addError('FloatingRateInterestCalculator: Missing principal or interestRate in context');
            return result;
        }
        IDayCountCalculator dcCalc = new GenericDayCountCalculator();
        Decimal fraction = dcCalc.getDayCountFraction(ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
        Decimal accrual = ctx.principal * (ctx.interestRate / 100) * fraction;
        result.setAmount(accrual.setScale(2, RoundingMode.HALF_EVEN));
        result.setResultType('Floating_Rate');
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }
}