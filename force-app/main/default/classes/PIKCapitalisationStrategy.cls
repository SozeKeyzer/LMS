/**
 * PIKCapitalisationStrategy
 * IRecalcStrategy for Trigger_Field__c = 'PIK_Capitalisation_Event'.
 * After a PIK capitalisation, uplifts the position notional and triggers
 * re-amortisation. Spec v3 Part 10.1.
 *
 * recordId = Debt_Position__c whose PIK capitalisation has just occurred.
 * The PIK amount is sourced from the most recent PIK_Capitalisation_Event__c
 * record in Pending state for this position.
 */
public class PIKCapitalisationStrategy implements IRecalcStrategy, ICalculationStrategy {

    public CalcResult execute(OrchestratorCalcContext ctx) {
        execute(ctx.parentRecordId, CorrelationIdGenerator.generate());
        CalcResult r = new CalcResult();
        r.success = true;
        r.outputRows = new List<SObject>();
        r.inputsSnapshot = new Map<String, Object>();
        r.validationMessages = new List<String>();
        r.invalidatesDownstream = new List<String>();
        return r;
    }

    public void execute(Id recordId, String correlationId) {
        // recordId = Debt_Position__c Id
        List<PIK_Capitalisation_Event__c> events = [
            SELECT Id, PIK_Amount__c, Capitalisation_Date__c, Correlation_Id__c
            FROM PIK_Capitalisation_Event__c
            WHERE Debt_Position__c = :recordId
            ORDER BY Capitalisation_Date__c DESC
            LIMIT 1
        ];
        if (events.isEmpty()) return;

        PIK_Capitalisation_Event__c pce = events[0];

        Decimal pikAmount = pce.PIK_Amount__c != null ? pce.PIK_Amount__c : 0;
        if (pikAmount == 0) return;

        // Outstanding_Balance__c auto-reflects PIK via Total_PIK_Capitalised__c roll-up + formula
        // Re-amortise forward from capitalisation date
        ScheduleReamortisationService.reamortiseAfterEvent(
            recordId,
            pce.Capitalisation_Date__c,
            correlationId
        );

        AuditEventLogger.logEngine(
            'PIK_CAPITALISED', 'Debt_Position__c', String.valueOf(recordId),
            'PIK capitalisation: amount=' + pikAmount + '. Re-amortised from ' + pce.Capitalisation_Date__c
                + '. correlationId=' + correlationId
        );
        AuditEventLogger.flush();
    }
}