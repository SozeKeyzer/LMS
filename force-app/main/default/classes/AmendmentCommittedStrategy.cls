/**
 * AmendmentCommittedStrategy
 * IRecalcStrategy for Trigger_Field__c = 'Amendment_Committed'.
 * After a Loan_Amendment is committed, regenerates Payment_Schedule rows
 * for all affected Debt_Positions. Spec v3 Part 10.1, Spec §5.3.
 *
 * recordId = Loan_Amendment__c that has just been committed.
 */
public class AmendmentCommittedStrategy implements IRecalcStrategy, ICalculationStrategy {

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
        List<Loan_Amendment__c> las = [
            SELECT Id, Name, Debt_Position__c
            FROM Loan_Amendment__c
            WHERE Id = :recordId
        ];
        if (las.isEmpty()) return;
        Loan_Amendment__c la = las[0];

        Set<Id> dpIds = new Set<Id>();
        if (la.Debt_Position__c != null) dpIds.add(la.Debt_Position__c);
        if (dpIds.isEmpty()) return;

        Integer regenCount = PaymentScheduleService.regenerateAfterAmendment(dpIds, la);

        AuditEventLogger.logEngine(
            'AMENDMENT_COMMITTED', 'Loan_Amendment__c', String.valueOf(recordId),
            'Schedule regenerated for ' + dpIds.size() + ' position(s). New rows=' + regenCount
                + '. correlationId=' + correlationId
        );
        AuditEventLogger.flush();
    }
}