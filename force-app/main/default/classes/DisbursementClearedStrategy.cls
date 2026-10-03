/**
 * DisbursementClearedStrategy
 * IRecalcStrategy for Trigger_Field__c = 'Disbursement_Cleared'.
 * Delegates to ScheduleReamortisationService to re-amortise the position
 * after a drawdown is cleared.
 * Spec v3 Part 10.1, Part 6.6.
 */
public class DisbursementClearedStrategy implements IRecalcStrategy {

    public void execute(Id recordId, String correlationId) {
        // recordId = Disbursement__c Id
        ScheduleReamortisationService.onDisbursementCleared(recordId);
    }
}