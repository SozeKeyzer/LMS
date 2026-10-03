/**
 * PIKInterestCalculator — implements IInterestCalculator
 * Payment In Kind: accrues same as fixed/floating but marks Is_PIK = true.
 * Does NOT contribute to Payment_Schedule.Interest_Due per Rule R5.
 * At period end, PeriodCloseBatch triggers PIK capitalisation into principal.
 */
public class PIKInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public PIKInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();
        IDayCountCalculator dcCalc = new GenericDayCountCalculator();
        Decimal fraction = dcCalc.getDayCountFraction(ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
        Decimal accrual = ctx.principal * (ctx.interestRate / 100) * fraction;
        result.setAmount(accrual.setScale(2, RoundingMode.HALF_EVEN));
        result.setResultType('PIK');
        result.putMeta('isPIK', true);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }
}