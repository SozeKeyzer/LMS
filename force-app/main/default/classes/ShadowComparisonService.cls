public with sharing class ShadowComparisonService {

    public class ComparisonResult {
        public Boolean isComparable;
        public String reason;
        public List<String> diffs;

        public ComparisonResult(Boolean isComparable, String reason, List<String> diffs) {
            this.isComparable = isComparable;
            this.reason       = reason;
            this.diffs        = diffs;
        }
    }

    public static ComparisonResult compare(Id dpId, Id projectionId) {
        Projection__c proj = [
            SELECT Id, Projected_Rows__c
            FROM Projection__c
            WHERE Id = :projectionId
        ];

        if (String.isBlank(proj.Projected_Rows__c)) {
            return new ComparisonResult(false, 'Empty projection: Projected_Rows__c is blank.',
                new List<String>());
        }

        List<Object> shadowRows = (List<Object>) JSON.deserializeUntyped(proj.Projected_Rows__c);

        List<Payment_Schedule__c> liveRows = [
            SELECT Id, Interest_Due__c, Principal_Due__c, Net_Due__c, Period_Start__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c IN ('Projected', 'Due')
            ORDER BY Period_Start__c ASC
        ];

        if (liveRows.size() != shadowRows.size()) {
            return new ComparisonResult(false,
                'Row count mismatch: live=' + liveRows.size() + ', shadow=' + shadowRows.size(),
                new List<String>());
        }

        List<String> diffs = new List<String>();
        for (Integer i = 0; i < liveRows.size() && i < shadowRows.size(); i++) {
            Map<String,Object> shadow = (Map<String,Object>) shadowRows[i];
            Payment_Schedule__c live  = liveRows[i];
            Decimal shadowInterest = shadow.get('interestDue') != null ? (Decimal) shadow.get('interestDue') : 0;
            Decimal liveInterest   = live.Interest_Due__c != null ? live.Interest_Due__c : 0;
            if (liveInterest != shadowInterest) {
                diffs.add('Row ' + i + ': interestDue live=' + liveInterest + ' shadow=' + shadowInterest);
            }
        }

        return new ComparisonResult(true, '', diffs);
    }

    public static void record(Calculation_Definition__mdt def,
                               Calculation_Run__c shadowRun,
                               CalcResult proposedResult) {

        // Find the most recent Locked run for this calc/parent to compare against
        Id parentId = shadowRun.Debt_Position__c != null
            ? shadowRun.Debt_Position__c
            : shadowRun.Financial_Instrument__c;

        List<Calculation_Run__c> lockedRuns = [
            SELECT Id, Calc_Version__c, Inputs_Snapshot__c, Output_Count__c
            FROM Calculation_Run__c
            WHERE Calc_Definition__c = :def.DeveloperName
              AND Run_Mode__c = 'Commit'
              AND Status__c = 'Success'
              AND (Debt_Position__c = :parentId OR Financial_Instrument__c = :parentId)
            ORDER BY Run_At__c DESC
            LIMIT 1
        ];

        String lockedVersion  = lockedRuns.isEmpty() ? def.Version__c : lockedRuns[0].Calc_Version__c;
        Id     lockedRunId    = lockedRuns.isEmpty() ? null : lockedRuns[0].Id;
        Integer lockedCount   = lockedRuns.isEmpty() ? 0 : (Integer)(lockedRuns[0].Output_Count__c ?? 0);
        Integer proposedCount = proposedResult.outputRows != null ? proposedResult.outputRows.size() : 0;

        Boolean differs = (proposedCount != lockedCount);
        String  summary = differs
            ? 'Row count changed: ' + lockedCount + ' → ' + proposedCount
            : 'Row counts match (' + proposedCount + ')';

        // If row counts match, do field-level diff on Interest_Due, Principal_Due, Total_Due
        if (!differs && proposedResult.outputRows != null && !proposedResult.outputRows.isEmpty()) {
            List<Object> proposedRows  = (List<Object>) proposedResult.outputRows;
            List<Object> lockedRows    = lockedRuns.isEmpty() ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(
                    lockedRuns[0].Inputs_Snapshot__c != null ? lockedRuns[0].Inputs_Snapshot__c : '[]'
                  );
            List<String> fieldDiffs    = new List<String>();
            Decimal interestDelta  = 0;
            Decimal principalDelta = 0;
            Decimal totalDueDelta  = 0;
            for (Integer i = 0; i < proposedRows.size() && i < lockedRows.size(); i++) {
                Map<String,Object> proposed = (Map<String,Object>) proposedRows[i];
                Map<String,Object> locked   = (Map<String,Object>) lockedRows[i];
                Decimal pInterest  = proposed.get('Interest_Due__c')  != null ? (Decimal) proposed.get('Interest_Due__c')  : 0;
                Decimal lInterest  = locked.get('Interest_Due__c')    != null ? (Decimal) locked.get('Interest_Due__c')    : 0;
                Decimal pPrincipal = proposed.get('Principal_Due__c') != null ? (Decimal) proposed.get('Principal_Due__c') : 0;
                Decimal lPrincipal = locked.get('Principal_Due__c')   != null ? (Decimal) locked.get('Principal_Due__c')   : 0;
                Decimal pTotal     = proposed.get('Net_Due__c')       != null ? (Decimal) proposed.get('Net_Due__c')       : 0;
                Decimal lTotal     = locked.get('Net_Due__c')         != null ? (Decimal) locked.get('Net_Due__c')         : 0;
                interestDelta  += pInterest  - lInterest;
                principalDelta += pPrincipal - lPrincipal;
                totalDueDelta  += pTotal     - lTotal;
            }
            differs = (interestDelta != 0 || principalDelta != 0 || totalDueDelta != 0);
            summary = differs
                ? 'Field diff: ΔInterest=' + interestDelta.setScale(2) + ', ΔPrincipal=' + principalDelta.setScale(2) + ', ΔTotal=' + totalDueDelta.setScale(2)
                : 'Output matches locked version. ' + proposedCount + ' rows compared, no field differences.';
        }

        Calculation_Shadow_Comparison__c comparison = new Calculation_Shadow_Comparison__c(
            Calc_Definition__c    = def.DeveloperName,
            Locked_Version__c     = lockedVersion,
            Proposed_Version__c   = def.Version__c,
            Locked_Run__c         = lockedRunId,
            Proposed_Output__c    = JSON.serialize(proposedResult.outputRows),
            Differences_Detected__c = differs,
            Difference_Summary__c = summary,
            Parent_Record_Id__c   = String.valueOf(parentId),
            Status__c             = 'Pending_Review'
        );
        insert comparison;
    }

    public static void archiveForCalc(String calcDeveloperName) {
        List<Calculation_Shadow_Comparison__c> comparisons = [
            SELECT Id FROM Calculation_Shadow_Comparison__c
            WHERE Calc_Definition__c = :calcDeveloperName
              AND Status__c != 'Archived'
        ];
        for (Calculation_Shadow_Comparison__c c : comparisons) {
            c.Status__c = 'Archived';
        }
        if (!comparisons.isEmpty()) update comparisons;
    }
}