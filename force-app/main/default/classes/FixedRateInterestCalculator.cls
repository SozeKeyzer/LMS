/**
 * FixedRateInterestCalculator — implements IInterestCalculator
 * For fixed-rate tranches: computes daily accrual as Principal x Rate x DayCountFraction.
 * Rate comes from CalcContext.interestRate (set from Interest_Period.All_In_Rate__c).
 * Enforces Rule R10 via isEngineOwned check in base.
 */
public class FixedRateInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public FixedRateInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();
        if (ctx.principal == null || ctx.interestRate == null || ctx.dayCountConvention == null) {
            result.addError('FixedRateInterestCalculator: Missing required context fields (principal, interestRate, dayCountConvention)');
            return result;
        }
        IDayCountCalculator dcCalc = new GenericDayCountCalculator();
        Decimal fraction = dcCalc.getDayCountFraction(ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
        Decimal accrual = ctx.principal * (ctx.interestRate / 100) * fraction;
        result.setAmount(accrual.setScale(2, RoundingMode.HALF_EVEN));
        result.setResultType('Fixed_Rate');
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }
}