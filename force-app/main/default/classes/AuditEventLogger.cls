/**
 * AuditEventLogger
 * Central logger for all LMS audit events. Uses spec-compliant field API names.
 * Collects events in a static list and flushes via single DML at end of operation.
 * Exposes @InvocableMethod so Flows can log events without a custom class.
 *
 * Field mapping (spec names):
 *   Source_Object__c     = API name of affected object
 *   Source_Record_Id__c  = 18-char Id of affected record
 *   Event_DateTime__c    = when it happened
 *   Actor_User__c        = who did it
 *   Before_Snapshot__c   = JSON before state
 *   After_Snapshot__c    = JSON after state
 *   Reason__c            = human-readable description
 *   Actor_System__c      = User / Batch / Flow / Integration / Scheduled
 */
public class AuditEventLogger {

    @TestVisible
    private static List<Audit_Event__c> pending = new List<Audit_Event__c>();

    /**
     * Queue an audit event. Call flush() at end of unit of work.
     */
    public static void log(
        String eventType,
        String objectName,
        String recordId,
        String source,
        String reason,
        String beforeSnapshot,
        String afterSnapshot
    ) {
        log(eventType, objectName, recordId, source, reason, beforeSnapshot, afterSnapshot, 'User');
    }

    public static void log(
        String eventType,
        String objectName,
        String recordId,
        String source,
        String reason,
        String beforeSnapshot,
        String afterSnapshot,
        String actorSystem
    ) {
        TriggerContext ctx = TriggerContext.getInstance();
        pending.add(new Audit_Event__c(
            Event_Type__c        = eventType,
            Source_Object__c     = objectName,
            Source_Record_Id__c  = recordId,
            Correlation_Id__c    = ctx.correlationId,
            Source__c            = source,
            Reason__c            = reason,
            Before_Snapshot__c   = beforeSnapshot,
            After_Snapshot__c    = afterSnapshot,
            Actor_User__c        = UserInfo.getUserId(),
            Event_DateTime__c    = DateTime.now(),
            Engine_Version__c    = CalculationEngineBase.ENGINE_VERSION,
            Actor_System__c      = actorSystem
        ));
    }

    /** Shorthand for engine-originated events. */
    public static void logEngine(String eventType, String objectName, String recordId, String reason) {
        log(eventType, objectName, recordId, 'System_Calculated', reason, null, null, 'Batch');
    }

    /** Shorthand for user-initiated events. */
    public static void logManual(String eventType, String objectName, String recordId, String reason) {
        log(eventType, objectName, recordId, 'Manual_Entry', reason, null, null, 'User');
    }

    /** Shorthand for Flow-initiated events. */
    public static void logFlow(String eventType, String objectName, String recordId, String reason) {
        log(eventType, objectName, recordId, 'Manual_Entry', reason, null, null, 'Flow');
    }

    /**
     * Flush all pending events to the database.
     * Call once per unit of work — never inside a loop.
     */
    public static void flush() {
        if (pending.isEmpty()) return;
        insert pending;
        pending.clear();
    }

    @TestVisible public static Integer pendingCount() { return pending.size(); }
    @TestVisible public static void clearPending() { pending.clear(); }

    // ── Invocable for Flows ──────────────────────────────────────────────────
    @InvocableMethod(
        label='Log Audit Event'
        description='Creates an Audit_Event__c record. Call from Flow instead of DML on Audit_Event directly.'
        category='LMS'
    )
    public static void logFromFlow(List<AuditLogRequest> requests) {
        for (AuditLogRequest req : requests) {
            log(req.eventType, req.objectApiName, req.recordId,
                req.source != null ? req.source : 'Manual_Entry',
                req.reason, null, null, 'Flow');
        }
        flush();
    }

    public class AuditLogRequest {
        @InvocableVariable(required=true  label='Event Type')       public String eventType;
        @InvocableVariable(required=true  label='Object API Name')  public String objectApiName;
        @InvocableVariable(required=false label='Record ID')        public String recordId;
        @InvocableVariable(required=false label='Source')           public String source;
        @InvocableVariable(required=false label='Reason')           public String reason;
    }
}
