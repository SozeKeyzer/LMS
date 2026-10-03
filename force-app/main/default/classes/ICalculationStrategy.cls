/**
 * @CalcDefinition
 * Name:        ICalculationStrategy
 * Description: Interface every calculation strategy must implement.
 *              Takes governance context, returns result. Same class serves
 *              Preview (no DML) and Commit (writes outputs) modes.
 * Lifecycle:   Locked
 */
public interface ICalculationStrategy {
    CalcResult execute(OrchestratorCalcContext ctx);
}