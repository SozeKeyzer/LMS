/**
 * BulletAmortisationCalculator — implements IAmortisationCalculator
 * Zero amortisation per period until maturity. On the final period,
 * Principal_Due = full Outstanding_Balance.
 */
public class BulletAmortisationCalculator extends CalculationEngineBase implements IAmortisationCalculator {

    public BulletAmortisationCalculator() { super(Mode.APPLY); }

    public EngineResult calculatePrincipalRepayment(CalcContext ctx) {
        EngineResult result = new EngineResult();
        Boolean isFinalPeriod = (Boolean) ctx.extras.get('isFinalPeriod');
        Decimal principal = isFinalPeriod == true ? ctx.principal : 0;
        result.setAmount(principal);
        result.setResultType('Bullet');
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculatePrincipalRepayment(ctx); }
}