/**
 * EqualInstalmentAmortisationCalculator — implements IAmortisationCalculator
 * Equal instalment (P+I constant per period). Computes annuity payment then
 * derives the principal component as: instalment - interest.
 */
public class EqualInstalmentAmortisationCalculator extends CalculationEngineBase implements IAmortisationCalculator {

    public EqualInstalmentAmortisationCalculator() { super(Mode.APPLY); }

    public EngineResult calculatePrincipalRepayment(CalcContext ctx) {
        EngineResult result = new EngineResult();
        Decimal principal = ctx.principal;
        Integer periodsPerYear = (ctx.extras != null && ctx.extras.get('periodsPerYear') != null)
            ? (Integer) ctx.extras.get('periodsPerYear') : 12;
        Decimal periodicRate = (ctx.interestRate / 100) / periodsPerYear;
        Integer totalPeriods = (Integer)(ctx.extras.get('totalPeriods') ?? 1);

        Decimal instalment;
        if (periodicRate == 0) {
            instalment = principal / totalPeriods;
        } else {
            Decimal factor = Math.pow((Double)(1 + periodicRate), totalPeriods);
            instalment = (principal * periodicRate * factor / (factor - 1)).setScale(2, RoundingMode.HALF_EVEN);
        }

        Decimal interestComponent = (principal * periodicRate).setScale(2, RoundingMode.HALF_EVEN);
        Decimal principalComponent = (instalment - interestComponent).setScale(2, RoundingMode.HALF_EVEN);

        result.setAmount(principalComponent);
        result.setResultType('Equal_Instalment');
        result.putMeta('totalInstalment', instalment);
        result.putMeta('interestComponent', interestComponent);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculatePrincipalRepayment(ctx); }
}