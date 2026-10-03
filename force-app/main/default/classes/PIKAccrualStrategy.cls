/**
 * PIKAccrualStrategy — ICalculationStrategy wrapper
 *
 * PIK (Payment In Kind) accrual capitalises interest into principal rather than
 * paying it in cash. Rows are Is_PIK__c = true; capitalisation into principal
 * is handled by a separate PIK_Capitalisation_Event when the period closes.
 *
 * Preview  → computes PIK Accrual_Daily__c rows in-memory. Nothing written.
 * Commit   → upserts computed rows by External_Id__c (idempotent re-runs).
 */
public with sharing class PIKAccrualStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages    = new List<String>();
        result.invalidatesDownstream = new List<String>{ 'Amortisation_Schedule' };

        List<Accrual_Daily__c> rows = FixedRateAccrualStrategy.buildAccrualRows(
            ctx.parentRecordId, true, 'PIK'
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