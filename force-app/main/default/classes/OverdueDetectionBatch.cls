/**
 * OverdueDetectionBatch — daily post-midnight.
 * Transitions Payment_Schedule Status: Due/Partial → Overdue when past due date.
 * Implements Database.Stateful so totalTransitioned accumulates across execute() chunks.
 */
public class OverdueDetectionBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer totalTransitioned = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Due_Date__c
            FROM Payment_Schedule__c
            WHERE Status__c IN ('Due', 'Partial') AND Due_Date__c < TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TriggerContext.getInstance().refreshCorrelationId();
        PaymentScheduleService.markOverdue((List<Payment_Schedule__c>) scope);
        totalTransitioned += scope.size();
        AuditEventLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        if (totalTransitioned > 0) {
            AuditEventLogger.logEngine(
                'OVERDUE_DETECTED',
                'Payment_Schedule__c',
                null,
                'OverdueDetectionBatch complete. ' + totalTransitioned + ' schedule row(s) transitioned to Overdue.'
            );
            AuditEventLogger.flush();
        }
    }
}