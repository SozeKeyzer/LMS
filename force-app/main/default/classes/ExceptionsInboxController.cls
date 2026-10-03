public with sharing class ExceptionsInboxController {

    @AuraEnabled(cacheable=true)
    public static List<ExceptionItemDTO> getExceptions() {
        List<ExceptionItemDTO> items = new List<ExceptionItemDTO>();

        // Failed calculation runs in the last 7 days
        List<Calculation_Run__c> failedRuns = [
            SELECT Id, Calc_Definition__c, Run_At__c
            FROM Calculation_Run__c
            WHERE Status__c = 'Failed'
              AND Run_At__c >= :Datetime.now().addDays(-7)
            ORDER BY Run_At__c DESC
            LIMIT 10
        ];
        if (!failedRuns.isEmpty()) {
            ExceptionItemDTO dto = new ExceptionItemDTO();
            dto.id          = failedRuns[0].Id;
            dto.severity    = 'error';
            dto.label       = 'Failed calculations — last 7 days';
            dto.detail      = failedRuns.size() + ' run(s) failed. Most recent: ' + failedRuns[0].Calc_Definition__c;
            dto.objectType  = 'Calculation_Run__c';
            dto.count       = String.valueOf(failedRuns.size());
            dto.actionLabel = 'Review';
            items.add(dto);
        }

        // Pending override requests
        List<Calculation_Override__c> pendingOverrides = [
            SELECT Id, Field_Overridden__c
            FROM Calculation_Override__c
            WHERE Status__c = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (!pendingOverrides.isEmpty()) {
            ExceptionItemDTO dto = new ExceptionItemDTO();
            dto.id          = pendingOverrides[0].Id;
            dto.severity    = 'warning';
            dto.label       = 'Override requests pending approval';
            dto.detail      = pendingOverrides.size() + ' override(s) awaiting sign-off';
            dto.objectType  = 'Calculation_Override__c';
            dto.count       = String.valueOf(pendingOverrides.size());
            dto.actionLabel = 'Approve';
            items.add(dto);
        }

        // Loans in manual mode
        List<Debt_Position__c> manualLoans = [
            SELECT Id, Name, Calc_Mode_Since__c
            FROM Debt_Position__c
            WHERE Calc_Mode__c = 'Manual'
            ORDER BY Calc_Mode_Since__c DESC
            LIMIT 10
        ];
        if (!manualLoans.isEmpty()) {
            ExceptionItemDTO dto = new ExceptionItemDTO();
            dto.id          = manualLoans[0].Id;
            dto.severity    = 'error';
            dto.label       = 'Loans in Manual Calculation Mode';
            dto.detail      = manualLoans.size() + ' loan(s) with engine suspended. Most recent: ' + manualLoans[0].Name;
            dto.objectType  = 'Debt_Position__c';
            dto.count       = String.valueOf(manualLoans.size());
            dto.actionLabel = 'Review';
            items.add(dto);
        }

        // Pending bulk recalculations
        List<Bulk_Recalculation_Run__c> pendingBulk = [
            SELECT Id, Calc_Definition__c
            FROM Bulk_Recalculation_Run__c
            WHERE Approval_Status__c = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        if (!pendingBulk.isEmpty()) {
            ExceptionItemDTO dto = new ExceptionItemDTO();
            dto.id          = pendingBulk[0].Id;
            dto.severity    = 'info';
            dto.label       = 'Bulk recalculations awaiting approval';
            dto.detail      = pendingBulk.size() + ' bulk run(s) pending sign-off';
            dto.objectType  = 'Bulk_Recalculation_Run__c';
            dto.count       = String.valueOf(pendingBulk.size());
            dto.actionLabel = 'Approve';
            items.add(dto);
        }

        return items;
    }

    public class ExceptionItemDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String severity;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
        @AuraEnabled public String objectType;
        @AuraEnabled public String count;
        @AuraEnabled public String actionLabel;
    }
}