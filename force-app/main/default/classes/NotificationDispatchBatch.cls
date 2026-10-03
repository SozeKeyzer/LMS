/** NotificationDispatchBatch — reads Notification_Rule__mdt, posts Chatter notifications. */
public class NotificationDispatchBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Event_Type__c, Source_Object__c, Source_Record_Id__c
            FROM Audit_Event__c
            WHERE Event_DateTime__c = TODAY
        ]);
    }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Read Notification_Rule__mdt and post per rule — full impl in Phase 1 LWC iteration
        AuditEventLogger.flush();
    }
    public void finish(Database.BatchableContext bc) {}
}