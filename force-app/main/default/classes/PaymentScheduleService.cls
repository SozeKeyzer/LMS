/**
 * PaymentScheduleService
 * Engine-driven schedule generation and promotion from Projection.
 * Handles Status transitions and Net_Due recalculation.
 */
public class PaymentScheduleService {

    /** Promote projected rows from a Projection to live Payment_Schedule records. */
    public static void promoteFromProjection(Projection__c projection) {
        if (String.isBlank(projection.Projected_Rows__c)) return;

        List<Object> rows = (List<Object>) JSON.deserializeUntyped(projection.Projected_Rows__c);
        List<Payment_Schedule__c> toInsert = new List<Payment_Schedule__c>();

        for (Object rowObj : rows) {
            Map<String,Object> row = (Map<String,Object>) rowObj;
            toInsert.add(new Payment_Schedule__c(
                Debt_Position__c      = (Id) row.get('debtPositionId'),
                Period_Start__c       = Date.valueOf((String) row.get('periodStart')),
                Period_End__c         = Date.valueOf((String) row.get('periodEnd')),
                Due_Date__c           = Date.valueOf((String) row.get('dueDate')),
                Principal_Due__c      = (Decimal)(row.get('principalDue') ?? 0),
                Interest_Due__c       = (Decimal)(row.get('interestDue') ?? 0),
                Fees_Due__c           = (Decimal)(row.get('feesDue') ?? 0),
                Status__c             = 'Projected',
                Is_Immutable__c       = false,
                Correlation_Id__c     = TriggerContext.getInstance().correlationId,
                Source__c             = 'System_Calculated',
                Engine_Version__c     = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c        = (String) row.get('externalId')
            ));
        }

        Schema.SObjectField extIdField = Payment_Schedule__c.Fields.External_Id__c;
        Database.upsert(toInsert, extIdField, false);

        update new Projection__c(Id = projection.Id, Status__c = 'Promoted', Promoted_DateTime__c = DateTime.now());
        AuditEventLogger.logEngine('SCHEDULE_GENERATED','Projection__c',String.valueOf(projection.Id),
            'Promoted ' + toInsert.size() + ' schedule rows from projection.');
        AuditEventLogger.flush();
    }

    /**
     * Creates replacement PS rows for every row superseded by the given amendment,
     * links them via Superseded_By__c, and returns the count of new rows created.
     *
     * Spec §5.3 — "PaymentScheduleService — generate, regenerate, supersede schedule."
     * Spec §5.2.1.2 — "new rows in Active state" after amendment supersession.
     * Spec §5.2.1 field table — "Superseded_By__c — replacement row after amendment."
     *
     * Period boundaries and principal are copied from the superseded rows — rate
     * amendments do not alter the principal schedule. Interest_Due is reset to 0;
     * DailyAccrualBatch/PeriodCloseBatch crystallises it under the new IRT terms.
     *
     * External_Id on new rows = {dpId}-{periodStart}-{amendmentIdSuffix8} so the
     * new rows coexist with the superseded originals without a unique-constraint conflict.
     */
    public static Integer regenerateAfterAmendment(Set<Id> dpIds, Loan_Amendment__c la) {
        List<Payment_Schedule__c> superseded = [
            SELECT Id, Debt_Position__c,
                   Period_Start__c, Period_End__c, Due_Date__c,
                   Principal_Due__c, Fees_Due__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c IN :dpIds
              AND Status__c = 'Superseded'
              AND Supersession_Amendment_Id__c = :String.valueOf(la.Id)
            ORDER BY Debt_Position__c, Period_Start__c ASC
        ];
        if (superseded.isEmpty()) return 0;

        // Pending Amendment IRT preferred for rate amendments; Applied IRT as fallback
        Map<Id, Interest_Rate_Terms__c> dpToIrt = resolvePendingAmendmentIrts(dpIds);
        resolveAppliedIrtFallback(dpIds, dpToIrt);

        String  corrId     = TriggerContext.getInstance().correlationId;
        String  laIdSuffix = String.valueOf(la.Id).right(8);
        Date    today      = Date.today();

        List<Payment_Schedule__c> newRows = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c old : superseded) {
            Interest_Rate_Terms__c irt     = dpToIrt.get(old.Debt_Position__c);
            String  basis                  = irt != null && String.isNotBlank(irt.Pricing_Basis__c)
                                                 ? irt.Pricing_Basis__c : 'Fixed';
            Boolean isFloating             = basis == 'Floating';
            String  rateFinStatus          = isFloating ? 'Projected_Rate' : 'Not_Applicable';
            Decimal placeholderSpread      = (isFloating && irt?.Spread__c != null)
                                                 ? irt.Spread__c : 0;
            // Period whose window spans today is current; everything else is future
            String cashStatus              = (old.Period_Start__c <= today && old.Period_End__c > today)
                                                 ? 'Due' : 'Projected';

            newRows.add(new Payment_Schedule__c(
                Debt_Position__c            = old.Debt_Position__c,
                Period_Start__c             = old.Period_Start__c,
                Period_End__c               = old.Period_End__c,
                Due_Date__c                 = old.Due_Date__c,
                Status__c                   = cashStatus,
                Rate_Finalisation_Status__c = rateFinStatus,
                Principal_Due__c            = old.Principal_Due__c != null ? old.Principal_Due__c : 0,
                Interest_Due__c             = 0,
                Fees_Due__c                 = old.Fees_Due__c   != null ? old.Fees_Due__c   : 0,
                Placeholder_Spread__c       = placeholderSpread,
                Placeholder_Base_Rate__c    = 0,
                Source__c                   = 'System_Calculated',
                Correlation_Id__c           = corrId,
                Engine_Version__c           = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c              = String.valueOf(old.Debt_Position__c)
                                                  + '-' + old.Period_Start__c.format()
                                                  + '-' + laIdSuffix
            ));
        }

        TriggerContext.getInstance().bypassGuards = true;
        try {
            insert newRows;
            // newRows[i].Id is populated after insert — list is parallel to superseded
            List<Payment_Schedule__c> linkUpdates = new List<Payment_Schedule__c>();
            for (Integer i = 0; i < superseded.size(); i++) {
                linkUpdates.add(new Payment_Schedule__c(
                    Id               = superseded[i].Id,
                    Superseded_By__c = newRows[i].Id
                ));
            }
            update linkUpdates;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'SCHEDULE_GENERATED', 'Loan_Amendment__c', String.valueOf(la.Id),
            'Schedule regenerated after amendment commit.'
                + ' Amendment=' + la.Name
                + '. New rows=' + newRows.size()
                + '. Superseded_By__c links written on old rows.');
        AuditEventLogger.flush();

        return newRows.size();
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static Map<Id, Interest_Rate_Terms__c> resolvePendingAmendmentIrts(Set<Id> dpIds) {
        Map<Id, Interest_Rate_Terms__c> result = new Map<Id, Interest_Rate_Terms__c>();
        for (Interest_Rate_Terms__c irt : [
            SELECT Id, Debt_Position__c, Pricing_Basis__c, Spread__c, Applicable_Fixed_Rate__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c IN :dpIds
              AND Application_Status__c = 'Pending'
              AND Rate_Reset_Trigger__c = 'Amendment'
            ORDER BY CreatedDate DESC
        ]) {
            if (!result.containsKey(irt.Debt_Position__c)) {
                result.put(irt.Debt_Position__c, irt);
            }
        }
        return result;
    }

    private static void resolveAppliedIrtFallback(
        Set<Id> dpIds,
        Map<Id, Interest_Rate_Terms__c> dpToIrt
    ) {
        Set<Id> missing = new Set<Id>(dpIds);
        missing.removeAll(dpToIrt.keySet());
        if (missing.isEmpty()) return;
        for (Interest_Rate_Terms__c irt : [
            SELECT Id, Debt_Position__c, Pricing_Basis__c, Spread__c, Applicable_Fixed_Rate__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c IN :missing
              AND Application_Status__c = 'Applied'
            ORDER BY Actual_Application_Date__c DESC NULLS LAST
        ]) {
            if (!dpToIrt.containsKey(irt.Debt_Position__c)) {
                dpToIrt.put(irt.Debt_Position__c, irt);
            }
        }
    }

    // ── Maker-Checker workflow (Spec v3 Part 6.5.3–6.5.6) ────────────────────

    /**
     * Maker generates a Draft schedule after all pre-conditions pass.
     * Sets Schedule_Generation_Status__c = 'Draft' and records the maker.
     * Spec v3 Part 6.5.3.
     */
    public static void generateDraft(Id dpId, Id makerId) {
        List<String> failures = ScheduleGenerationPreConditions.validate(dpId);
        if (!failures.isEmpty()) {
            throw new ScheduleGenerationException(
                'Pre-condition check failed:\n• ' + String.join(failures, '\n• ')
            );
        }

        // Generate the period grid, then re-stamp the rows Draft — Spec Part 5.2.1.2:
        // "Draft ... Schedule rows: Status = Draft" / "Pending_Review ... Status = Draft (still)".
        // ScheduleGenerationService itself still writes 'Projected' by default because it is
        // also used by AmortisationScheduleStrategy for post-Active recalculation, where
        // 'Projected' retains its normal (non-draft) meaning.
        List<Payment_Schedule__c> generatedRows = ScheduleGenerationService.generate(dpId);

        TriggerContext.getInstance().bypassGuards = true;
        try {
            if (!generatedRows.isEmpty()) {
                List<Payment_Schedule__c> stampDraft = new List<Payment_Schedule__c>();
                for (Payment_Schedule__c row : generatedRows) {
                    stampDraft.add(new Payment_Schedule__c(Id = row.Id, Status__c = 'Draft'));
                }
                update stampDraft;
            }
            update new Debt_Position__c(
                Id = dpId,
                Schedule_Generation_Status__c    = 'Draft',
                Schedule_Generation_Maker__c     = makerId,
                Schedule_Draft_Created_DateTime__c = DateTime.now()
            );
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'SCHEDULE_DRAFT_GENERATED', 'Debt_Position__c', String.valueOf(dpId),
            'Draft schedule generated by maker: ' + makerId
        );
        AuditEventLogger.flush();
    }

    /**
     * Maker submits the Draft for checker review.
     * Enforces that submitter is the original maker (4-eyes). Spec v3 Part 6.5.4.
     */
    public static void submitForReview(Id dpId, Id makerId, String notes) {
        Debt_Position__c dp = [
            SELECT Id, Schedule_Generation_Status__c, Schedule_Generation_Maker__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        if (dp.Schedule_Generation_Status__c != 'Draft') {
            throw new ScheduleGenerationException(
                'Cannot submit: schedule is not in Draft status (current: ' + dp.Schedule_Generation_Status__c + ')'
            );
        }
        if (dp.Schedule_Generation_Maker__c != makerId) {
            throw new ScheduleGenerationException(
                'Only the original maker may submit for review.'
            );
        }

        TriggerContext.getInstance().bypassGuards = true;
        try {
            update new Debt_Position__c(
                Id = dpId,
                Schedule_Generation_Status__c = 'Pending_Review',
                Schedule_Generation_Notes__c  = notes
            );
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'SCHEDULE_SUBMITTED_FOR_REVIEW', 'Debt_Position__c', String.valueOf(dpId),
            'Schedule submitted for review by maker: ' + makerId + '. Notes: ' + notes
        );
        AuditEventLogger.flush();

        NotificationService.fire('SCHEDULE_SUBMITTED_FOR_REVIEW', dp);
    }

    /**
     * Checker approves the Pending_Review schedule.
     * Enforces 4-eyes: checker must differ from maker. Spec v3 Part 6.5.5.
     */
    public static void approve(Id dpId, Id checkerId, String notes) {
        Debt_Position__c dp = [
            SELECT Id, Schedule_Generation_Status__c, Schedule_Generation_Maker__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        if (dp.Schedule_Generation_Status__c != 'Pending_Review') {
            throw new ScheduleGenerationException(
                'Cannot approve: schedule is not Pending_Review (current: ' + dp.Schedule_Generation_Status__c + ')'
            );
        }
        if (dp.Schedule_Generation_Maker__c == checkerId) {
            throw new ScheduleGenerationException(
                '4-eyes violation: checker must differ from maker.'
            );
        }

        // Promote draft rows to their live cash status. Rate_Finalisation_Status was already
        // set correctly at generation time (ScheduleGenerationService) and is left untouched.
        // Spec Part 5.2.1.2: past periods -> Paid, current/future -> Due. Rows are also locked
        // (Is_Immutable__c) so Protected_Field__mdt can guard them from here on.
        List<Payment_Schedule__c> draftRows = [
            SELECT Id, Period_End__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c = 'Draft'
        ];
        Date today = Date.today();
        List<Payment_Schedule__c> rowUpdates = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c row : draftRows) {
            rowUpdates.add(new Payment_Schedule__c(
                Id              = row.Id,
                Status__c       = row.Period_End__c < today ? 'Paid' : 'Due',
                Is_Immutable__c = true
            ));
        }

        TriggerContext.getInstance().bypassGuards = true;
        try {
            update new Debt_Position__c(
                Id = dpId,
                Schedule_Generation_Status__c  = 'Active',
                Schedule_Generation_Checker__c = checkerId,
                Schedule_Activated_DateTime__c = DateTime.now(),
                Schedule_Generation_Notes__c   = notes
            );
            if (!rowUpdates.isEmpty()) update rowUpdates;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'SCHEDULE_APPROVED', 'Debt_Position__c', String.valueOf(dpId),
            'Schedule approved by checker: ' + checkerId + '. Notes: ' + notes
                + '. Rows promoted to live status: ' + rowUpdates.size()
        );
        AuditEventLogger.flush();
    }

    /**
     * Checker rejects the Pending_Review schedule.
     * Deletes draft rows, resets status to Not_Generated. Spec v3 Part 6.5.6.
     */
    public static void reject(Id dpId, Id checkerId, String reason) {
        Debt_Position__c dp = [
            SELECT Id, Schedule_Generation_Status__c, Schedule_Generation_Maker__c,
                   Correlation_Id__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        if (dp.Schedule_Generation_Status__c != 'Pending_Review') {
            throw new ScheduleGenerationException(
                'Cannot reject: schedule is not Pending_Review (current: ' + dp.Schedule_Generation_Status__c + ')'
            );
        }
        if (dp.Schedule_Generation_Maker__c == checkerId) {
            throw new ScheduleGenerationException(
                '4-eyes violation: checker must differ from maker.'
            );
        }

        // Delete Projected rows that were part of the draft
        List<Payment_Schedule__c> draftRows = [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c = 'Projected'
              AND Is_Immutable__c = false
        ];

        TriggerContext.getInstance().bypassGuards = true;
        try {
            if (!draftRows.isEmpty()) delete draftRows;

            update new Debt_Position__c(
                Id = dpId,
                Schedule_Generation_Status__c  = 'Not_Generated',
                Schedule_Last_Reject_Reason__c = reason,
                Schedule_Generation_Checker__c = null,
                Schedule_Activated_DateTime__c = null
            );
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'SCHEDULE_REJECTED', 'Debt_Position__c', String.valueOf(dpId),
            'Schedule rejected by checker: ' + checkerId + '. Reason: ' + reason
                + '. Deleted ' + draftRows.size() + ' draft row(s).'
        );
        AuditEventLogger.flush();
    }

    public class ScheduleGenerationException extends Exception {}

    // ── End maker-checker ─────────────────────────────────────────────────────

    /** Transition Due/Partial schedules to Overdue when past due date. Called by OverdueDetectionBatch. */
    public static void markOverdue(List<Payment_Schedule__c> schedules) {
        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : schedules) {
            if ((ps.Status__c == 'Due' || ps.Status__c == 'Partial') && ps.Due_Date__c < Date.today()) {
                toUpdate.add(new Payment_Schedule__c(Id = ps.Id, Status__c = 'Overdue'));
            }
        }
        if (toUpdate.isEmpty()) return;
        TriggerContext.getInstance().bypassGuards = true;
        try {
            update toUpdate;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }
    }
}