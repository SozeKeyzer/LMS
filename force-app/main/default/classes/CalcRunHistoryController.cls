public with sharing class CalcRunHistoryController {

    @AuraEnabled(cacheable=true)
    public static List<Calculation_Run__c> getRuns(Id recordId, String objectApiName) {
        if (objectApiName == 'Financial_Instrument__c') {
            return [
                SELECT Id, Name, Calc_Definition__c, Calc_Version__c, Run_At__c,
                       Run_Mode__c, Trigger_Source__c, Status__c,
                       Output_Count__c, Duration_Ms__c, Inputs_Snapshot__c,
                       Error_Message__c, Run_By__c
                FROM Calculation_Run__c
                WHERE Financial_Instrument__c = :recordId
                ORDER BY Run_At__c DESC
                LIMIT 100
            ];
        }
        return [
            SELECT Id, Name, Calc_Definition__c, Calc_Version__c, Run_At__c,
                   Run_Mode__c, Trigger_Source__c, Status__c,
                   Output_Count__c, Duration_Ms__c, Inputs_Snapshot__c,
                   Error_Message__c, Run_By__c
            FROM Calculation_Run__c
            WHERE Debt_Position__c = :recordId
            ORDER BY Run_At__c DESC
            LIMIT 100
        ];
    }
}