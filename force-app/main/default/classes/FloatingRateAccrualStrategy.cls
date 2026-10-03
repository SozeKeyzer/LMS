/**
 * FloatingRateAccrualStrategy — ICalculationStrategy wrapper
 *
 * The floating rate is already materialised into Interest_Period__c.All_In_Rate__c
 * by the rate-fixing process, so computation is identical to the fixed-rate path.
 *
 * Preview  → computes Accrual_Daily__c rows in-memory. Nothing written.
 * Commit   → upserts computed rows by External_Id__c (idempotent re-runs).
 */
public with sharing class FloatingRateAccrualStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages    = new List<String>();
        result.invalidatesDownstream = new List<String>{ 'Holder_Economics_Allocation' };

        List<Accrual_Daily__c> rows = FixedRateAccrualStrategy.buildAccrualRows(
            ctx.parentRecordId, false, 'FL'
        );

        if (ctx.runMode == 'Preview') {
            result.outputRows = rows;
            result.inputsSnapshot = new Map<String, Object>{
                'mode' => 'Preview', 'projectedRows' => rows.size()
            };
        } else {
            if (!rows.isEmpty()) {
                Database.upsert(rows, Accrual_Daily__c.Fields.External_Id__c, false);
            }
            result.outputRows = rows;
            result.inputsSnapshot = new Map<String, Object>{
                'mode' => 'Commit', 'accrualRows' => rows.size()
            };
        }
        return result;
    }
}