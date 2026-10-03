public with sharing class HolderEconomicsController {

    @AuraEnabled(cacheable=true)
    public static List<HolderDTO> getHolders(Id recordId, String mode) {
        List<HolderDTO> result = new List<HolderDTO>();
        // Aggregate mode: show Debt_Position__c tranches as proxy holders until
        // a dedicated Participation__c object is introduced.
        List<Debt_Position__c> positions = 'aggregate'.equals(mode)
            ? [
                SELECT Id, Name, Initial_Margin__c
                FROM Debt_Position__c
                WHERE Financial_Instrument__c = :recordId
                ORDER BY Name ASC
              ]
            : [
                SELECT Id, Name, Initial_Margin__c
                FROM Debt_Position__c
                WHERE Id = :recordId
              ];

        Integer count = positions.size();
        for (Debt_Position__c dp : positions) {
            HolderDTO dto = new HolderDTO();
            dto.holderId  = dp.Id;
            dto.holderName = dp.Name;
            dto.commitment = null;
            dto.pctShare   = count > 0 ? (1.0 / count) : 0;
            result.add(dto);
        }
        return result;
    }

    public class HolderDTO {
        @AuraEnabled public String  holderId;
        @AuraEnabled public String  holderName;
        @AuraEnabled public Decimal commitment;
        @AuraEnabled public Decimal pctShare;
    }
}