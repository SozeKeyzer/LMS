/**
 * IAmortisationCalculator
 * Implemented by: BulletAmortisationCalculator, EqualPrincipalAmortisationCalculator,
 * EqualInstalmentAmortisationCalculator, SculptedAmortisationCalculator (Phase 1)
 */
public interface IAmortisationCalculator {
    /**
     * Calculate the principal repayment amount for a given payment period.
     * @return EngineResult with calculatedAmount = principal component for this period
     */
    EngineResult calculatePrincipalRepayment(CalcContext ctx);
}
