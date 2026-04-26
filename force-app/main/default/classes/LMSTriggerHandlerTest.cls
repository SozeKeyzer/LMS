@IsTest
private class LMSTriggerHandlerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();
    }

    @IsTest
    static void testInsertCreatesAuditEvent() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Guard Test FI');
        insert fi;
        List<Audit_Event__c> events = [
            SELECT Event_Type__c, Source_Object__c
            FROM Audit_Event__c
            WHERE Source_Object__c = 'Financial_Instrument__c'
        ];
        Assert.isFalse(events.isEmpty(), 'Should have created an audit event on insert');
        Assert.areEqual('RECORD_CREATED', events[0].Event_Type__c);
    }

    @IsTest
    static void testStatusChangeLogsEvent() {
        Financial_Instrument__c fi = new Financial_Instrument__c(
            Name = 'Status Test FI',
            Status__c = 'Active'
        );
        insert fi;
        AuditEventLogger.clearPending();
        fi.Status__c = 'Closed';
        update fi;
        List<Audit_Event__c> events = [
            SELECT Event_Type__c, Reason__c
            FROM Audit_Event__c
            WHERE Source_Object__c = 'Financial_Instrument__c'
            AND Event_Type__c = 'STATUS_CHANGED'
        ];
        Assert.isFalse(events.isEmpty(), 'Status change should be audited');
    }
}
