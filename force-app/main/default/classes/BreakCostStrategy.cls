/**
 * BreakCostStrategy — ICalculationStrategy wrapper
 * Delegates to BreakCostCalculator at runtime using the Basis_Code from the prepayment event.
 * For the readiness panel this shows as on-demand with no required inputs on the DP itself.
 */
public with sharing class BreakCostStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages = new List<String>();
        result.invalidatesDownstream = new List<String>();
        result.outputRows = new List<SObject>();
        result.inputsSnapshot = new Map<String, Object>{
            'parentRecordId' => String.valueOf(ctx.parentRecordId),
            'calcVersion'    => ctx.calcVersion,
            'runMode'        => ctx.runMode,
            'note'           => 'Break cost requires a Prepayment_Event record. Use the Break Cost action on the event.'
        };
        return result;
    }
}