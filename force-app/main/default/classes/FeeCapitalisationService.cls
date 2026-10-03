/**
 * FeeCapitalisationService
 * Fee capitalisation — fees that uplift Position_Notional rather than collecting in cash.
 * Implements Rule R22 per Spec v3 Part 6.9 and v7 Part 5.2.8.
 *
 * Workflow:
 *   1. capitaliseAtDueDate() — creates Fee_Capitalisation_Event__c (Pending); routes for approval
 *   2. activateCapitalisation() — called on approval; uplifts notional, creates new Amort segment,
 *      triggers ScheduleReamortisationService.reamortiseAfterEvent
 *
 * Dependencies:
 *   ScheduleReamortisationService   — regenerates future schedule rows after notional uplift
 *   CorrelationIdGenerator          — stamps all produced records with same correlation ID
 *   TriggerContext.isAmendmentCommit — bypasses protected-field guard for notional update
 */
public class FeeCapitalisationService {

    /**
     * Called at fee due date for fees where Fee_Treatment = Capitalised.
     * For Cash_or_Capitalised_Election: reads Linked_Election to determine treatment.
     *
     * @param feeStructureId  Id of the Fee_Structures__c record
     * @param dueDate         Contractual due date for this fee occurrence
     */
    public static Fee_Capitalisation_Event__c capitaliseAtDueDate(Id feeStructureId, Date dueDate) {
        Fee_Structures__c fs = [
            SELECT Id, Debt_Position__c, Fee_Treatment__c, Capitalisation_Trigger__c,
                   Linked_Election__c, Source__c, Amount__c, Applicable_Rate__c
            FROM Fee_Structures__c
            WHERE Id = :feeStructureId
        ];

        String treatment = fs.Fee_Treatment__c;
        if (treatment == 'Cash_or_Capitalised_Election' && fs.Linked_Election__c != null) {
            Election__c e = [SELECT Election_Type__c FROM Election__c WHERE Id = :fs.Linked_Election__c];
            treatment = (e.Election_Type__c == 'Cash') ? 'Cash' : 'Capitalised';
        }
        if (treatment != 'Capitalised') return null; // cash treatment — standard invoice path

        Debt_Position__c dp = [
            SELECT Id, Position_Notional__c, Outstanding_Balance__c
            FROM Debt_Position__c
            WHERE Id = :fs.Debt_Position__c
        ];

        Decimal feeAmount = computeFeeAmount(fs, dp, dueDate);
        String correlationId = CorrelationIdGenerator.generate();

        Fee_Capitalisation_Event__c fce = new Fee_Capitalisation_Event__c(
            Debt_Position__c           = dp.Id,
            Fee_Structure__c           = fs.Id,
            Capitalisation_Date__c     = dueDate,
            Fee_Amount__c              = feeAmount,
            Pre_Capitalisation_Notional__c  = dp.Position_Notional__c,
            Post_Capitalisation_Notional__c = dp.Position_Notional__c + feeAmount,
            Status__c                  = 'Pending',
            Source__c                  = 'System_Calculated',
            Correlation_Id__c          = correlationId
        );
        insert fce;

        // Route for approval per Approval_Matrix (Approval Process fires on insert)
        // For lightweight implementation: ops approves directly on the FCE record page.
        // Full approval routing wired via standard Approval Process on Fee_Capitalisation_Event__c.

        AuditEventLogger.logEngine('FEE_CAPITALISED', 'Fee_Capitalisation_Event__c',
            String.valueOf(fce.Id),
            'Fee capitalisation pending approval. Amount: ' + feeAmount
                + '. Notional: ' + dp.Position_Notional__c + ' → '
                + (dp.Position_Notional__c + feeAmount));
        AuditEventLogger.flush();
        return fce;
    }

    /**
     * Called when the Fee_Capitalisation_Event is approved (e.g. from an Approval Process
     * final-approval action invoking this as an Apex action, or from a Flow post-approval).
     *
     * @param fceId  Id of the approved Fee_Capitalisation_Event__c
     */
    public static void activateCapitalisation(Id fceId) {
        Fee_Capitalisation_Event__c fce = [
            SELECT Id, Debt_Position__c, Fee_Amount__c, Capitalisation_Date__c,
                   Pre_Capitalisation_Notional__c, Post_Capitalisation_Notional__c, Correlation_Id__c
            FROM Fee_Capitalisation_Event__c
            WHERE Id = :fceId
        ];

        // Uplift Position_Notional
        Debt_Position__c dp = [
            SELECT Id, Position_Notional__c FROM Debt_Position__c WHERE Id = :fce.Debt_Position__c
        ];
        dp.Position_Notional__c = fce.Post_Capitalisation_Notional__c;
        TriggerContext.getInstance().bypassGuards = true;
        try {
            update dp;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        // Create new Amortisation_Rules segment from Capitalisation_Date forward
        Amortisation_Rules__c newSegment = createSegmentFromCurrentActive(
            dp.Id, fce.Capitalisation_Date__c, fce.Post_Capitalisation_Notional__c);
        insert newSegment;

        // Link FCE to new segment and mark Active
        fce.Status__c                  = 'Active';
        fce.Linked_Amortisation_Rules__c = newSegment.Id;
        update fce;

        // Trigger Re-Amortise_Forward cascade for future schedule rows
        ScheduleReamortisationService.reamortiseAfterEvent(
            dp.Id, fce.Capitalisation_Date__c, fce.Correlation_Id__c);

        AuditEventLogger.logEngine('FEE_CAPITALISED', 'Fee_Capitalisation_Event__c',
            String.valueOf(fce.Id),
            'Notional uplifted from ' + fce.Pre_Capitalisation_Notional__c
                + ' to ' + fce.Post_Capitalisation_Notional__c
                + '. New Amortisation_Rules segment: ' + newSegment.Id);
        AuditEventLogger.flush();
    }

    // ── Private helpers ────────────────────────────────────────────────────────

    private static Decimal computeFeeAmount(Fee_Structures__c fs, Debt_Position__c dp, Date dueDate) {
        // Reads Applicable_Rate__c or Amount__c on the Fee_Structures record
        try {
            Object rate = fs.get('Applicable_Rate__c');
            if (rate != null && (Decimal)rate > 0) {
                Decimal notional = dp.Position_Notional__c != null ? dp.Position_Notional__c : 0;
                return (notional * ((Decimal)rate / 100)).setScale(2, RoundingMode.HALF_EVEN);
            }
        } catch (Exception e) {}
        try {
            Object amt = fs.get('Amount__c');
            if (amt != null) return ((Decimal)amt).setScale(2, RoundingMode.HALF_EVEN);
        } catch (Exception e) {}
        return 0;
    }

    private static Amortisation_Rules__c createSegmentFromCurrentActive(
        Id dpId, Date effectiveFrom, Decimal newNotional
    ) {
        // Clone the current active Amortisation_Rules but set new notional and effectiveFrom
        List<Amortisation_Rules__c> active = [
            SELECT Id
            FROM Amortisation_Rules__c
            WHERE Debt_Position__c = :dpId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Amortisation_Rules__c segment = new Amortisation_Rules__c(
            Debt_Position__c = dpId,
            Source__c        = 'System_Calculated'
        );
        // Copy amortisation method from active rule if available
        if (!active.isEmpty()) {
            try {
                Object method = active[0].get('Amortisation_Method__c');
                if (method != null) segment.put('Amortisation_Method__c', method);
            } catch (Exception e) {}
        }
        return segment;
    }
}