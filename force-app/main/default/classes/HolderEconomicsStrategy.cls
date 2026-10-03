/**
 * HolderEconomicsStrategy — ICalculationStrategy wrapper
 * Placeholder for holder economics allocation. Depends on Amortisation_Schedule being current.
 * Full implementation uses WaterfallAllocator services.
 */
public with sharing class HolderEconomicsStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages = new List<String>();
        result.invalidatesDownstream = new List<String>();
        result.outputRows = new List<SObject>();
        result.inputsSnapshot = new Map<String, Object>{
            'parentRecordId' => String.valueOf(ctx.parentRecordId),
            'calcVersion'    => ctx.calcVersion,
            'runMode'        => ctx.runMode
        };
        return result;
    }
}