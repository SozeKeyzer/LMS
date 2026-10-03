public with sharing class CashflowChartController {

    @AuraEnabled(cacheable=true)
    public static List<CashflowDTO> getCashflows(Id recordId, String mode) {
        List<CashflowDTO> result = new List<CashflowDTO>();
        List<Payment_Schedule__c> schedules = 'aggregate'.equals(mode)
            ? [
                SELECT Id, Due_Date__c, Principal_Due__c, Interest_Due__c, Fees_Due__c
                FROM Payment_Schedule__c
                WHERE Debt_Position__r.Financial_Instrument__c = :recordId
                  AND Status__c NOT IN ('Superseded', 'Cancelled')
                ORDER BY Due_Date__c ASC
                LIMIT 200
              ]
            : [
                SELECT Id, Due_Date__c, Principal_Due__c, Interest_Due__c, Fees_Due__c
                FROM Payment_Schedule__c
                WHERE Debt_Position__c = :recordId
                  AND Status__c NOT IN ('Superseded', 'Cancelled')
                ORDER BY Due_Date__c ASC
                LIMIT 200
              ];
        for (Payment_Schedule__c ps : schedules) {
            CashflowDTO dto = new CashflowDTO();
            dto.period    = ps.Due_Date__c     != null ? String.valueOf(ps.Due_Date__c) : '';
            dto.principal = ps.Principal_Due__c != null ? ps.Principal_Due__c : 0;
            dto.interest  = ps.Interest_Due__c  != null ? ps.Interest_Due__c  : 0;
            dto.fees      = ps.Fees_Due__c      != null ? ps.Fees_Due__c      : 0;
            dto.pik       = 0;
            result.add(dto);
        }
        return result;
    }

    public class CashflowDTO {
        @AuraEnabled public String period;
        @AuraEnabled public Decimal principal;
        @AuraEnabled public Decimal interest;
        @AuraEnabled public Decimal fees;
        @AuraEnabled public Decimal pik;
    }
}