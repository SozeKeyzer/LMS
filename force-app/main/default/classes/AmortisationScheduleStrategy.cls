/**
 * AmortisationScheduleStrategy — ICalculationStrategy wrapper
 *
 * Preview  → runs ScheduleGenerationService inside a savepoint/rollback to show
 *            exactly what the new schedule would look like without persisting anything.
 *            Uses forceRegen=true so existing Projected rows are updated in-place by
 *            the upsert — no Status changes, no validation rules triggered.
 *
 * Commit   → regenerates the schedule using forceRegen=true (upsert over existing rows),
 *            then supersedes any orphaned Projected rows (periods no longer in the new
 *            schedule) with Superseded_By__c pointing to the first new row. Only Projected
 *            rows that are not manually locked are eligible. Due/Paid rows are never touched.
 */
public with sharing class AmortisationScheduleStrategy implements ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        CalcResult result = new CalcResult();
        result.success = true;
        result.validationMessages    = new List<String>();
        result.invalidatesDownstream = new List<String>{ 'Holder_Economics_Allocation' };

        if (ctx.runMode == 'Preview') {
            // previewRows() computes rows purely in-memory — no DML, no savepoint.
            // Principal_Due__c is correctly set by computePrincipal().
            // Total_Due__c is a formula (null here) — LWC computes it client-side.
            List<Payment_Schedule__c> rows =
                ScheduleGenerationService.previewRows(ctx.parentRecordId);
            List<SObject> preview = new List<SObject>();
            for (Integer i = 0; i < rows.size() && i < 200; i++) {
                preview.add(rows[i]);
            }
            result.outputRows = preview;
            result.inputsSnapshot = new Map<String, Object>{
                'mode'          => 'Preview',
                'projectedRows' => result.outputRows.size()
            };

        } else {
            // ── Snapshot existing unlocked Projected rows ─────────────────────
            List<Payment_Schedule__c> existingProjected = [
                SELECT Id, External_Id__c FROM Payment_Schedule__c
                WHERE Debt_Position__c = :ctx.parentRecordId
                  AND Status__c = 'Projected'
                  AND Locked_By_Manual_Mode__c = false
            ];
            Map<String, Id> oldExtIdToId = new Map<String, Id>();
            for (Payment_Schedule__c ps : existingProjected) {
                if (ps.External_Id__c != null) {
                    oldExtIdToId.put(ps.External_Id__c, ps.Id);
                }
            }

            // ── Generate new schedule (upserts over existing in-place) ────────
            List<Payment_Schedule__c> newRows =
                ScheduleGenerationService.generate(ctx.parentRecordId, true);

            Set<String> newExtIds = new Set<String>();
            for (Payment_Schedule__c nr : newRows) {
                if (nr.External_Id__c != null) newExtIds.add(nr.External_Id__c);
            }

            // ── Supersede orphaned Projected rows ─────────────────────────────
            // Orphans: were Projected before the run but have no matching period
            // in the new schedule (e.g. maturity moved earlier).
            Id supersededById = newRows.isEmpty() ? null : newRows[0].Id;
            List<Payment_Schedule__c> toSupersede = new List<Payment_Schedule__c>();
            for (String extId : oldExtIdToId.keySet()) {
                if (!newExtIds.contains(extId)) {
                    toSupersede.add(new Payment_Schedule__c(
                        Id                    = oldExtIdToId.get(extId),
                        Status__c             = 'Superseded',
                        Superseded_By__c      = supersededById,
                        Supersession_Reason__c = 'Recalculation'
                    ));
                }
            }
            if (!toSupersede.isEmpty() && supersededById != null) {
                update toSupersede;
            }

            // ── Return the final set of Projected rows ────────────────────────
            result.outputRows = [
                SELECT Id, External_Id__c, Due_Date__c, Period_Start__c, Period_End__c,
                       Principal_Due__c, Interest_Due__c, Total_Due__c, Status__c
                FROM Payment_Schedule__c
                WHERE Debt_Position__c = :ctx.parentRecordId
                  AND Status__c = 'Projected'
                ORDER BY Due_Date__c ASC
                LIMIT 200
            ];
            result.inputsSnapshot = new Map<String, Object>{
                'mode'           => 'Commit',
                'supersededRows' => toSupersede.size(),
                'generatedRows'  => result.outputRows.size()
            };
        }

        return result;
    }
}