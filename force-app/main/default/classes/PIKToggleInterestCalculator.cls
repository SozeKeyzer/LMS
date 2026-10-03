/**
 * PIKToggleInterestCalculator — implements IInterestCalculator
 * Split election: reads PIK_Percentage from context extras to split accrual into cash and PIK portions.
 * Cash portion flows to Payment_Schedule.Interest_Due (can age/become Overdue).
 * PIK portion capitalises via PIK_Capitalisation_Event at period end (Rule R7).
 */
public class PIKToggleInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public PIKToggleInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();
        IDayCountCalculator dcCalc = new GenericDayCountCalculator();
        Decimal fraction = dcCalc.getDayCountFraction(ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
        Decimal totalAccrual = ctx.principal * (ctx.interestRate / 100) * fraction;
        Decimal pikPct = (Decimal)(ctx.extras.containsKey('pikPercentage') ? ctx.extras.get('pikPercentage') : 0);
        Decimal pikAmount  = (totalAccrual * pikPct / 100).setScale(2, RoundingMode.HALF_EVEN);
        Decimal cashAmount = (totalAccrual - pikAmount).setScale(2, RoundingMode.HALF_EVEN);
        result.setAmount(cashAmount);
        result.setResultType('PIK_Toggle');
        result.putMeta('pikAmount', pikAmount);
        result.putMeta('cashAmount', cashAmount);
        result.putMeta('isPIKSplit', true);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }
}