public with sharing class CascadePreviewController {

    @AuraEnabled
    public static CascadePreviewDTO preview(Id recordId, String objectApiName,
                                             String fieldApiName, Object newValue) {
        CascadePreviewDTO result = new CascadePreviewDTO();
        List<Calculation_Definition__mdt> affectedDefs = [
            SELECT DeveloperName, MasterLabel, Cascade_Trigger_Fields__c
            FROM Calculation_Definition__mdt
            WHERE Active__c = true
              AND Lifecycle_State__c = 'Locked'
              AND Trigger_Object__c = :objectApiName
        ];
        result.affectedCalcs = new List<CalcImpactDTO>();
        for (Calculation_Definition__mdt def : affectedDefs) {
            if (String.isNotBlank(fieldApiName) &&
                String.isNotBlank(def.Cascade_Trigger_Fields__c) &&
                def.Cascade_Trigger_Fields__c.contains(fieldApiName)) {
                CalcImpactDTO impact = new CalcImpactDTO();
                impact.calcName = def.MasterLabel;
                impact.outputRowsExpected = 0;
                impact.outputDeltas = new Map<String, Object>();
                result.affectedCalcs.add(impact);
            }
        }
        result.downstreamStale = new List<String>();
        return result;
    }

    @AuraEnabled
    public static String commitCascade(Id recordId, String objectApiName,
                                       String fieldApiName, Object newValue,
                                       String reason, String explanation) {
        Cascade_Run__c cascadeRun = new Cascade_Run__c(
            Triggering_Object__c = objectApiName,
            Triggering_Record_Id__c = recordId,
            Trigger_Event__c = fieldApiName + ' changed',
            Change_Reason__c = reason,
            Change_Explanation__c = explanation,
            Triggered_By__c = UserInfo.getUserId(),
            Triggered_At__c = Datetime.now(),
            Status__c = 'Success'
        );
        insert cascadeRun;
        return JSON.serialize(cascadeRun);
    }

    public class CascadePreviewDTO {
        @AuraEnabled public List<CalcImpactDTO> affectedCalcs;
        @AuraEnabled public List<String> downstreamStale;
    }

    public class CalcImpactDTO {
        @AuraEnabled public String calcName;
        @AuraEnabled public Integer outputRowsExpected;
        @AuraEnabled public Map<String, Object> outputDeltas;
    }
}