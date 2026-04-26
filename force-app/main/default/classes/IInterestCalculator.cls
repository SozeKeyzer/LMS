/**
 * IInterestCalculator
 * Implemented by: FixedRateInterestCalculator, FloatingRateInterestCalculator,
 * PIKInterestCalculator, PIKToggleInterestCalculator, StepUpInterestCalculator (Phase 1+)
 */
public interface IInterestCalculator {
    /**
     * Calculate interest for one day given the context.
     * @return EngineResult with calculatedAmount = daily accrual amount
     */
    EngineResult calculate(CalcContext ctx);
}
