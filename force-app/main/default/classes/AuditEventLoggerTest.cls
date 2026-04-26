@IsTest
private class AuditEventLoggerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();
    }

    @IsTest
    static void testLogQueuesEvent() {
        AuditEventLogger.log('RECORD_CREATED', 'Debt_Position__c', 'a001', 'System_Calculated', 'Test event', null, null);
        Assert.areEqual(1, AuditEventLogger.pendingCount(), 'Should have 1 pending event');
    }

    @IsTest
    static void testFlushInsertsAndClears() {
        AuditEventLogger.log('RECORD_CREATED', 'Debt_Position__c', 'a001', 'System_Calculated', 'Test event', null, null);
        AuditEventLogger.flush();
        Assert.areEqual(0, AuditEventLogger.pendingCount(), 'Pending should be clear after flush');
        List<Audit_Event__c> events = [SELECT Id, Event_Type__c, Source_Object__c, Actor_System__c FROM Audit_Event__c];
        Assert.areEqual(1, events.size(), 'Should have inserted 1 Audit Event');
        Assert.areEqual('RECORD_CREATED', events[0].Event_Type__c);
        Assert.areEqual('Debt_Position__c', events[0].Source_Object__c);
        Assert.areEqual('User', events[0].Actor_System__c);
    }

    @IsTest
    static void testLogEngineSetsBatchActor() {
        AuditEventLogger.logEngine('RECORD_CREATED', 'Debt_Position__c', 'a001', 'Engine created record');
        AuditEventLogger.flush();
        Audit_Event__c ev = [SELECT Actor_System__c, Source__c FROM Audit_Event__c LIMIT 1];
        Assert.areEqual('Batch', ev.Actor_System__c);
        Assert.areEqual('System_Calculated', ev.Source__c);
    }

    @IsTest
    static void testMultipleEventsShareCorrelationId() {
        AuditEventLogger.log('RECORD_CREATED', 'Debt_Position__c', 'a001', 'System_Calculated', 'First', null, null);
        AuditEventLogger.log('RECORD_UPDATED', 'Debt_Position__c', 'a001', 'System_Calculated', 'Second', null, null);
        AuditEventLogger.flush();
        List<Audit_Event__c> events = [SELECT Correlation_Id__c FROM Audit_Event__c ORDER BY CreatedDate];
        Assert.areEqual(2, events.size());
        Assert.areEqual(events[0].Correlation_Id__c, events[1].Correlation_Id__c,
            'Both events should share the same Correlation ID');
    }

    @IsTest
    static void testNoUpdateOnAuditEvent() {
        AuditEventLogger.logEngine('RECORD_CREATED', 'Debt_Position__c', 'a001', 'Test');
        AuditEventLogger.flush();
        Audit_Event__c ev = [SELECT Id, Reason__c FROM Audit_Event__c LIMIT 1];
        try {
            ev.Reason__c = 'Tampered';
            update ev;
            Assert.fail('Should have thrown exception — audit events are insert-only');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('immutable'), 'Error should mention immutability');
        }
    }
}
