/**
 * EqualPrincipalAmortisationCalculator — implements IAmortisationCalculator
 * Original principal divided equally across all periods.
 * Principal_Due = originalPrincipal / totalPeriods.
 */
public class EqualPrincipalAmortisationCalculator extends CalculationEngineBase implements IAmortisationCalculator {

    public EqualPrincipalAmortisationCalculator() { super(Mode.APPLY); }

    public EngineResult calculatePrincipalRepayment(CalcContext ctx) {
        EngineResult result = new EngineResult();
        Decimal originalPrincipal = (Decimal)(ctx.extras.get('originalPrincipal') ?? ctx.principal);
        Integer totalPeriods = (Integer)(ctx.extras.get('totalPeriods') ?? 1);
        if (totalPeriods <= 0) totalPeriods = 1;
        Integer currentPeriod = (ctx.extras != null && ctx.extras.get('currentPeriod') != null)
            ? (Integer) ctx.extras.get('currentPeriod') : 0;
        Decimal due;
        if (currentPeriod > 0 && currentPeriod == totalPeriods) {
            // Last period: absorb accumulated rounding so total repaid equals originalPrincipal exactly
            Decimal perPeriod = (originalPrincipal / totalPeriods).setScale(2, RoundingMode.HALF_UP);
            due = (originalPrincipal - perPeriod * (totalPeriods - 1)).setScale(2, RoundingMode.HALF_UP);
        } else {
            due = (originalPrincipal / totalPeriods).setScale(2, RoundingMode.HALF_UP);
        }
        result.setAmount(due);
        result.setResultType('Equal_Principal');
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculatePrincipalRepayment(ctx); }
}