/**
 * AmendmentProjectionComparisonController
 *
 * Apex controller for the amendmentProjectionComparison LWC.
 * Returns the current open Payment_Schedule rows for the amendment's affected DP
 * alongside the linked Projection header so the LWC can render the side-by-side
 * impact comparison.
 *
 * with sharing + AccessLevel.USER_MODE enforce OWD, sharing rules, and FLS
 * at the query layer — the LWC never receives data the running user cannot see.
 */
public with sharing class AmendmentProjectionComparisonController {

    /**
     * Generates the preview Projection for an amendment and links it via Recalc_Projection__c.
     * Called from the Amendment_Wizard LWC when ops clicks "Generate Preview" before submitting.
     * Not cacheable — has side effects (creates Projection__c, updates amendment).
     *
     * @return  Id of the created Projection__c, or null if preview could not be generated
     *          (no DP resolved, no IRT found, or no future Payment_Schedule rows exist).
     */
    @AuraEnabled
    public static Id generatePreview(Id amendmentId) {
        return AmendmentService.generatePreview(amendmentId);
    }

    @AuraEnabled(cacheable=true)
    public static ComparisonResult getScheduleComparison(Id amendmentId) {
        if (amendmentId == null) {
            return new ComparisonResult();
        }

        // Fetch the amendment record — need Scope, DP, FI, Recalc_Projection, effective date
        List<Loan_Amendment__c> laList = Database.queryWithBinds(
            'SELECT Id, Name, Scope__c, Amendment_Type__c, ' +
            'Debt_Position__c, Financial_Instrument__c, ' +
            'Recalc_Projection__c, Actual_Effective_Date__c, ' +
            'Proposed_Effective_Date__c, Status__c ' +
            'FROM Loan_Amendment__c WHERE Id = :amendmentId LIMIT 1',
            new Map<String, Object>{ 'amendmentId' => amendmentId },
            AccessLevel.USER_MODE
        );
        if (laList.isEmpty()) return new ComparisonResult();
        Loan_Amendment__c la = laList[0];

        ComparisonResult result       = new ComparisonResult();
        result.amendmentName          = la.Name;
        result.amendmentType          = la.Amendment_Type__c;
        result.scope                  = la.Scope__c;
        result.amendmentStatus        = la.Status__c;
        result.proposedEffectiveDate  = la.Proposed_Effective_Date__c;
        result.actualEffectiveDate    = la.Actual_Effective_Date__c;

        // Resolve the DP Ids affected by this amendment
        Set<Id> dpIds = resolveDpIds(la);
        if (!dpIds.isEmpty()) {
            // Use Actual_Effective_Date when set (post-commit); fall back to Proposed for Draft/Pending
            Date effectiveDate = la.Actual_Effective_Date__c != null
                ? la.Actual_Effective_Date__c
                : la.Proposed_Effective_Date__c;
            result.currentSchedule = queryCurrentSchedule(dpIds, effectiveDate);
        }

        // Projection header — available once the Recalc_Projection link is set
        if (la.Recalc_Projection__c != null) {
            result.projectionSummary = queryProjectionSummary(la.Recalc_Projection__c);
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Set<Id> resolveDpIds(Loan_Amendment__c la) {
        Set<Id> ids = new Set<Id>();
        if (la.Scope__c == 'Position' && la.Debt_Position__c != null) {
            ids.add(la.Debt_Position__c);
        } else if (la.Scope__c == 'Facility' && la.Financial_Instrument__c != null) {
            Id fiId = la.Financial_Instrument__c;
            for (SObject dp : Database.queryWithBinds(
                'SELECT Id FROM Debt_Position__c WHERE Financial_Instrument__c = :fiId',
                new Map<String, Object>{ 'fiId' => fiId },
                AccessLevel.USER_MODE
            )) {
                ids.add((Id) dp.get('Id'));
            }
        }
        return ids;
    }

    private static List<ScheduleRow> queryCurrentSchedule(Set<Id> dpIds, Date effectiveDate) {
        String soql =
            'SELECT Id, Period_Start__c, Period_End__c, Due_Date__c, ' +
            'Principal_Due__c, Interest_Due__c, Total_Due__c, ' +
            'Status__c, Debt_Position__c ' +
            'FROM Payment_Schedule__c ' +
            'WHERE Debt_Position__c IN :dpIds ' +
            '  AND Status__c IN (\'Projected\', \'Due\') ';
        if (effectiveDate != null) {
            soql += ' AND Period_Start__c >= :effectiveDate ';
        }
        soql += 'ORDER BY Period_Start__c ASC';

        List<ScheduleRow> rows = new List<ScheduleRow>();
        for (SObject ps : Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'dpIds' => dpIds, 'effectiveDate' => effectiveDate },
            AccessLevel.USER_MODE
        )) {
            ScheduleRow r        = new ScheduleRow();
            r.recordId           = (Id)      ps.get('Id');
            r.periodStart        = (Date)    ps.get('Period_Start__c');
            r.periodEnd          = (Date)    ps.get('Period_End__c');
            r.dueDate            = (Date)    ps.get('Due_Date__c');
            r.principalDue       = (Decimal) ps.get('Principal_Due__c');
            r.interestDue        = (Decimal) ps.get('Interest_Due__c');
            r.totalDue           = (Decimal) ps.get('Total_Due__c');
            r.status             = (String)  ps.get('Status__c');
            r.isAffectedByAmend  = effectiveDate != null && r.periodStart != null
                                    && r.periodStart >= effectiveDate;
            rows.add(r);
        }
        return rows;
    }

    private static ProjectionSummary queryProjectionSummary(Id projectionId) {
        List<SObject> results = Database.queryWithBinds(
            'SELECT Id, Name, Status__c, Projection_Type__c, ' +
            'Generated_DateTime__c, Projected_Rows__c ' +
            'FROM Projection__c WHERE Id = :projectionId LIMIT 1',
            new Map<String, Object>{ 'projectionId' => projectionId },
            AccessLevel.USER_MODE
        );
        if (results.isEmpty()) return null;

        SObject proj            = results[0];
        ProjectionSummary ps   = new ProjectionSummary();
        ps.projectionId        = (Id)       proj.get('Id');
        ps.projectionName      = (String)   proj.get('Name');
        ps.status              = (String)   proj.get('Status__c');
        ps.projectionType      = (String)   proj.get('Projection_Type__c');
        ps.generatedDateTime   = (DateTime) proj.get('Generated_DateTime__c');

        // Projected_Rows__c is a LongTextArea JSON payload (spec 5.2.10).
        // Parse the JSON array and map each entry to a typed ProjectedRow DTO.
        String rowsJson = (String) proj.get('Projected_Rows__c');
        ps.projectedRows = parseProjectedRows(rowsJson);
        return ps;
    }

    private static List<ProjectedRow> parseProjectedRows(String rowsJson) {
        List<ProjectedRow> out = new List<ProjectedRow>();
        if (String.isBlank(rowsJson)) return out;
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(rowsJson);
            for (Object item : raw) {
                Map<String, Object> m = (Map<String, Object>) item;
                ProjectedRow r        = new ProjectedRow();
                r.periodStart         = strToDate(m.get('periodStart'));
                r.periodEnd           = strToDate(m.get('periodEnd'));
                r.dueDate             = strToDate(m.get('dueDate'));
                r.principalDue        = toDecimal(m.get('principalDue'));
                r.interestDue         = toDecimal(m.get('interestDue'));
                r.totalDue            = toDecimal(m.get('totalDue'));
                r.status              = String.valueOf(m.get('status') ?? 'Projected');
                out.add(r);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'AmendmentProjectionComparisonController: failed to parse Projected_Rows__c JSON — ' +
                e.getMessage());
        }
        return out;
    }

    private static Date strToDate(Object val) {
        if (val == null) return null;
        try { return Date.valueOf(String.valueOf(val)); }
        catch (Exception e) { return null; }
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return null;
        try { return Decimal.valueOf(String.valueOf(val)); }
        catch (Exception e) { return null; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DTOs — serialised by the @AuraEnabled framework
    // ─────────────────────────────────────────────────────────────────────────

    public class ComparisonResult {
        @AuraEnabled public String            amendmentName;
        @AuraEnabled public String            amendmentType;
        @AuraEnabled public String            scope;
        @AuraEnabled public String            amendmentStatus;
        @AuraEnabled public Date              proposedEffectiveDate;
        @AuraEnabled public Date              actualEffectiveDate;
        @AuraEnabled public List<ScheduleRow> currentSchedule  = new List<ScheduleRow>();
        @AuraEnabled public ProjectionSummary projectionSummary;
    }

    public class ScheduleRow {
        @AuraEnabled public Id      recordId;
        @AuraEnabled public Date    periodStart;
        @AuraEnabled public Date    periodEnd;
        @AuraEnabled public Date    dueDate;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal totalDue;
        @AuraEnabled public String  status;
        @AuraEnabled public Boolean isAffectedByAmend;  // true = this row falls on/after the effective date
    }

    public class ProjectionSummary {
        @AuraEnabled public Id                  projectionId;
        @AuraEnabled public String              projectionName;
        @AuraEnabled public String              status;
        @AuraEnabled public String              projectionType;
        @AuraEnabled public DateTime            generatedDateTime;
        @AuraEnabled public List<ProjectedRow>  projectedRows = new List<ProjectedRow>();
    }

    public class ProjectedRow {
        @AuraEnabled public Date    periodStart;
        @AuraEnabled public Date    periodEnd;
        @AuraEnabled public Date    dueDate;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal totalDue;
        @AuraEnabled public String  status;
    }
}