public with sharing class CalculationOrchestrator {

    public static CalcResult run(String calcName, Id parentId, String runMode) {

        // Load the requested (Locked) definition
        List<Calculation_Definition__mdt> defs = [
            SELECT DeveloperName, MasterLabel, Active__c, Strategy_Class__c,
                   Trigger_Object__c, Invalidates__c, Version__c, Lifecycle_State__c
            FROM Calculation_Definition__mdt
            WHERE DeveloperName = :calcName
            LIMIT 1
        ];
        if (defs.isEmpty()) {
            return CalcResult.failed('Calculation definition not found: ' + calcName);
        }
        Calculation_Definition__mdt def = defs[0];

        if (!def.Active__c) {
            return CalcResult.failed('Inactive');
        }

        // Check Calc_Mode__c on parent
        String soql = 'SELECT Id, Calc_Mode__c FROM ' + def.Trigger_Object__c + ' WHERE Id = :parentId';
        List<SObject> parents = Database.query(soql);
        if (parents.isEmpty()) {
            return CalcResult.failed('Parent record not found: ' + parentId);
        }
        SObject parent = parents[0];

        if ((String) parent.get('Calc_Mode__c') == 'Manual' && runMode == 'Commit') {
            createSkippedRun(def, parentId, 'Manual mode active');
            return CalcResult.skipped('Record is in Manual mode');
        }

        OrchestratorCalcContext ctx = new OrchestratorCalcContext();
        ctx.parentRecordId      = parentId;
        ctx.parentObjectApiName = def.Trigger_Object__c;
        ctx.relatedRecords      = new Map<String, SObject>();
        ctx.runMode             = runMode;
        ctx.calcDeveloperName   = def.DeveloperName;
        ctx.calcVersion         = def.Version__c;

        ICalculationStrategy strategy;
        try {
            Type strategyType = Type.forName(def.Strategy_Class__c);
            if (strategyType == null) {
                return CalcResult.failed('Strategy class not found: ' + def.Strategy_Class__c);
            }
            strategy = (ICalculationStrategy) strategyType.newInstance();
        } catch (Exception e) {
            return CalcResult.failed('Strategy instantiation failed: ' + e.getMessage());
        }

        Long startMs = System.currentTimeMillis();
        CalcResult result;
        String errorMsg = null;
        try {
            result = strategy.execute(ctx);
        } catch (Exception e) {
            result   = CalcResult.failed(e.getMessage());
            errorMsg = e.getMessage();
        }
        Long durationMs = System.currentTimeMillis() - startMs;

        // Preview is a pure dry-run — return immediately with no DB writes.
        // Inserting a Calculation_Run__c for preview would pollute run history
        // and risk picklist-validation failures on Run_Mode__c.
        if (runMode == 'Preview') {
            return result;
        }

        Calculation_Run__c runRecord = new Calculation_Run__c(
            Calc_Definition__c   = def.DeveloperName,
            Calc_Version__c      = def.Version__c,
            Run_At__c            = Datetime.now(),
            Run_Mode__c          = runMode,
            Trigger_Source__c    = runMode == 'Shadow' ? 'Shadow' : 'Manual_Button',
            Run_By__c            = UserInfo.getUserId(),
            Status__c            = result.success ? 'Success' : 'Failed',
            Output_Count__c      = result.outputRows != null ? result.outputRows.size() : 0,
            Duration_Ms__c       = durationMs,
            Inputs_Snapshot__c   = JSON.serialize(result.inputsSnapshot),
            Error_Message__c     = errorMsg
        );
        if (def.Trigger_Object__c == 'Debt_Position__c') {
            runRecord.Debt_Position__c = parentId;
        } else if (def.Trigger_Object__c == 'Financial_Instrument__c') {
            runRecord.Financial_Instrument__c = parentId;
        }
        insert runRecord;

        if (runMode == 'Commit' && result.success) {
            if (result.outputRows != null && !result.outputRows.isEmpty()) {
                List<SObject> toInsert = new List<SObject>();
                for (SObject row : result.outputRows) {
                    if (row.Id == null) {
                        // Set provenance fields before insert
                        setProvenance(row, def, runRecord.Id);
                        toInsert.add(row);
                    } else {
                        // Row already persisted by strategy (e.g. via existing service)
                        // Update provenance fields on already-saved rows
                        updateProvenance(row, def, runRecord.Id);
                    }
                }
                if (!toInsert.isEmpty()) insert toInsert;
            }
            if (String.isNotBlank(def.Invalidates__c)) {
                CalcInvalidationService.flagStale(def.Invalidates__c, parentId);
            }
            // Auto-detect and run any Proposed version in Shadow mode for comparison
            runShadowIfProposedExists(calcName, parentId, result);
        }

        if (runMode == 'Shadow' && result.success) {
            ShadowComparisonService.record(def, runRecord, result);
        }

        return result;
    }

    // Sets provenance fields on a new output row before insert
    private static void setProvenance(SObject row, Calculation_Definition__mdt def, Id runId) {
        try {
            row.put('Calc_Source__c', def.DeveloperName);
        } catch (Exception e) {}
        try {
            row.put('Calc_Version__c', def.Version__c);
        } catch (Exception e) {}
        try {
            row.put('Calculation_Run__c', runId);
        } catch (Exception e) {}
        try {
            row.put('Has_Override__c', false);
        } catch (Exception e) {}
        try {
            row.put('Locked_By_Manual_Mode__c', false);
        } catch (Exception e) {}
    }

    // Updates provenance fields on already-saved rows (returned with IDs by strategies)
    private static void updateProvenance(SObject row, Calculation_Definition__mdt def, Id runId) {
        SObject toUpdate = row.getSObjectType().newSObject(row.Id);
        Boolean needsUpdate = false;
        try { toUpdate.put('Calc_Source__c', def.DeveloperName); needsUpdate = true; } catch (Exception e) {}
        try { toUpdate.put('Calc_Version__c', def.Version__c);   needsUpdate = true; } catch (Exception e) {}
        try { toUpdate.put('Calculation_Run__c', runId);         needsUpdate = true; } catch (Exception e) {}
        if (needsUpdate) {
            try { update toUpdate; } catch (Exception e) {}
        }
    }

    // Scenario 1: when a Commit runs the Locked version, also run any Proposed version
    // in Shadow mode to populate Calculation_Shadow_Comparison__c automatically
    private static void runShadowIfProposedExists(String lockedCalcName, Id parentId,
                                                   CalcResult lockedResult) {
        // Get the MasterLabel of the locked calc first
        List<Calculation_Definition__mdt> locked = [
            SELECT MasterLabel FROM Calculation_Definition__mdt
            WHERE DeveloperName = :lockedCalcName LIMIT 1
        ];
        if (locked.isEmpty()) return;
        String masterLabel = locked[0].MasterLabel;

        // Find any Proposed version with the same label
        List<Calculation_Definition__mdt> proposed = [
            SELECT DeveloperName FROM Calculation_Definition__mdt
            WHERE MasterLabel = :masterLabel
              AND Lifecycle_State__c = 'Proposed'
              AND Active__c = true
            LIMIT 1
        ];
        if (proposed.isEmpty()) return;

        CalculationOrchestrator.run(proposed[0].DeveloperName, parentId, 'Shadow');
    }

    private static void createSkippedRun(Calculation_Definition__mdt def, Id parentId, String reason) {
        Calculation_Run__c skipped = new Calculation_Run__c(
            Calc_Definition__c = def.DeveloperName,
            Calc_Version__c    = def.Version__c,
            Run_At__c          = Datetime.now(),
            Run_Mode__c        = 'Skipped',
            Status__c          = 'Skipped',
            Error_Message__c   = reason,
            Trigger_Source__c  = 'On_Save',
            Run_By__c          = UserInfo.getUserId()
        );
        if (def.Trigger_Object__c == 'Debt_Position__c') {
            skipped.Debt_Position__c = parentId;
        } else if (def.Trigger_Object__c == 'Financial_Instrument__c') {
            skipped.Financial_Instrument__c = parentId;
        }
        insert skipped;
    }
}