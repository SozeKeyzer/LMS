public with sharing class AuditEventController {

    @AuraEnabled(cacheable=true)
    public static List<AuditEventDTO> getAuditEventsByCorrelationId(String correlationId) {
        if (String.isBlank(correlationId)) return new List<AuditEventDTO>();
        List<Audit_Event__c> events = [
            SELECT Id, Event_Type__c, Event_DateTime__c, Actor_System__c,
                   Source_Object__c, Source_Record_Id__c, Reason__c,
                   Actor_User__r.Name, Source__c
            FROM Audit_Event__c
            WHERE Correlation_Id__c = :correlationId
            ORDER BY Event_DateTime__c ASC
            LIMIT 200
        ];
        List<AuditEventDTO> result = new List<AuditEventDTO>();
        for (Audit_Event__c ae : events) {
            AuditEventDTO dto = new AuditEventDTO();
            dto.id            = ae.Id;
            dto.eventType     = ae.Event_Type__c;
            dto.eventDateTime = ae.Event_DateTime__c != null ? ae.Event_DateTime__c.format() : null;
            dto.actorSystem   = ae.Actor_System__c;
            dto.sourceObject  = ae.Source_Object__c;
            dto.sourceRecordId = ae.Source_Record_Id__c;
            dto.reason        = ae.Reason__c;
            dto.actorName     = ae.Actor_User__r != null ? ae.Actor_User__r.Name : null;
            dto.recordLink    = String.isNotBlank(ae.Source_Record_Id__c)
                ? '/lightning/r/' + ae.Source_Object__c + '/' + ae.Source_Record_Id__c + '/view'
                : null;
            result.add(dto);
        }
        return result;
    }

    public class AuditEventDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String eventType;
        @AuraEnabled public String eventDateTime;
        @AuraEnabled public String actorSystem;
        @AuraEnabled public String sourceObject;
        @AuraEnabled public String sourceRecordId;
        @AuraEnabled public String reason;
        @AuraEnabled public String actorName;
        @AuraEnabled public String recordLink;
    }
}