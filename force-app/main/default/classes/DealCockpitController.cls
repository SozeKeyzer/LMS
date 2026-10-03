public with sharing class DealCockpitController {

    @AuraEnabled(cacheable=true)
    public static DealSummaryDTO getSummary(Id financialInstrumentId) {
        DealSummaryDTO dto = new DealSummaryDTO();
        dto.tranches = [
            SELECT Id, Name, Calc_Mode__c, Calc_Mode_Since__c,
                   Day_Count_Convention__c, Initial_Margin__c, Initial_Benchmark__c
            FROM Debt_Position__c
            WHERE Financial_Instrument__c = :financialInstrumentId
            ORDER BY Name ASC
        ];
        dto.trancheCount = dto.tranches.size();
        return dto;
    }

    public class DealSummaryDTO {
        @AuraEnabled public List<Debt_Position__c> tranches;
        @AuraEnabled public Integer trancheCount;
        @AuraEnabled public String fallbackReason;
    }
}