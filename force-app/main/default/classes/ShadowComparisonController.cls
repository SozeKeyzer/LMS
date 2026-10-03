public with sharing class ShadowComparisonController {

    @AuraEnabled(cacheable=true)
    public static List<Calculation_Shadow_Comparison__c> getComparisons(String calcDeveloperName) {
        if (String.isBlank(calcDeveloperName)) {
            return [
                SELECT Id, Name, Calc_Definition__c, Locked_Version__c,
                       Proposed_Version__c, Differences_Detected__c,
                       Difference_Summary__c, Parent_Record_Id__c, Status__c
                FROM Calculation_Shadow_Comparison__c
                WHERE Status__c != 'Archived'
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Calc_Definition__c, Locked_Version__c,
                   Proposed_Version__c, Differences_Detected__c,
                   Difference_Summary__c, Parent_Record_Id__c, Status__c
            FROM Calculation_Shadow_Comparison__c
            WHERE Calc_Definition__c = :calcDeveloperName
              AND Status__c != 'Archived'
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }
}