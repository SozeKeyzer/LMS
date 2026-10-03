/**
 * NotificationService
 * Stub dispatcher for engine-generated notifications. Translates internal event names
 * to Notification_Rule__mdt entries and delegates to NotificationDispatchBatch.
 * Full implementation delivers Chatter notifications, custom notifications, or emails
 * per the rule's Delivery_Channel. Spec v7 Part 5.5 (schedule lifecycle notifications),
 * Part 6.6 (drawdown re-amortisation), Part 9.5 (make-whole).
 */
public class NotificationService {

    /**
     * Fire a named notification event. Reads Notification_Rule__mdt for matching
     * Event_Type and dispatches asynchronously. Safe to call from any trigger context.
     *
     * @param eventType  Matches Notification_Rule__mdt.Event_Type__c
     * @param record     SObject that triggered the event (Debt_Position, IRT, etc.)
     */
    public static void fire(String eventType, SObject record) {
        if (String.isBlank(eventType) || record == null) return;

        // Write an Audit_Event so ops can see the notification was fired regardless of delivery
        String recordId = String.valueOf(record.Id);
        String objectType = String.valueOf(record.getSObjectType());
        AuditEventLogger.logEngine(
            'NOTIFICATION_FIRED', objectType, recordId,
            'Notification event fired: ' + eventType
        );
        // Actual delivery via NotificationDispatchBatch nightly sweep picks up today's events.
        // For time-sensitive notifications, enqueue inline using System.enqueueJob if needed.
    }
}