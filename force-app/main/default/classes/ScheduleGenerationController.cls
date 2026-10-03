/**
 * ScheduleGenerationController
 * Apex controller for the scheduleGeneratorWizard (maker) and scheduleApproverView (checker)
 * LWCs. Thin wrapper over ScheduleGenerationPreConditions and PaymentScheduleService's
 * maker-checker methods — all business rules and 4-eyes enforcement live there.
 */
public with sharing class ScheduleGenerationController {

    @AuraEnabled(cacheable=true)
    public static StatusDTO getStatus(Id dpId) {
        Debt_Position__c dp = [
            SELECT Id, Name, Status__c, Schedule_Generation_Status__c,
                   Schedule_Generation_Maker__c, Schedule_Generation_Maker__r.Name,
                   Schedule_Generation_Checker__c, Schedule_Generation_Checker__r.Name,
                   Schedule_Draft_Created_DateTime__c, Schedule_Activated_DateTime__c,
                   Schedule_Generation_Notes__c, Schedule_Last_Reject_Reason__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        StatusDTO dto = new StatusDTO();
        dto.dpId                    = dp.Id;
        dto.dpName                  = dp.Name;
        dto.dpStatus                = dp.Status__c;
        dto.scheduleGenerationStatus = dp.Schedule_Generation_Status__c == null
            ? 'Not_Generated' : dp.Schedule_Generation_Status__c;
        dto.makerId                 = dp.Schedule_Generation_Maker__c;
        dto.makerName               = dp.Schedule_Generation_Maker__r?.Name;
        dto.checkerId               = dp.Schedule_Generation_Checker__c;
        dto.checkerName             = dp.Schedule_Generation_Checker__r?.Name;
        dto.draftCreatedDateTime    = dp.Schedule_Draft_Created_DateTime__c;
        dto.activatedDateTime       = dp.Schedule_Activated_DateTime__c;
        dto.notes                   = dp.Schedule_Generation_Notes__c;
        dto.lastRejectReason        = dp.Schedule_Last_Reject_Reason__c;
        dto.currentUserId           = UserInfo.getUserId();
        dto.preconditionFailures    = ScheduleGenerationPreConditions.validate(dpId);

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<DraftRowDTO> getDraftRows(Id dpId) {
        List<DraftRowDTO> result = new List<DraftRowDTO>();
        for (Payment_Schedule__c row : [
            SELECT Id, Period_Start__c, Period_End__c, Due_Date__c,
                   Principal_Due__c, Fees_Due__c, Rate_Finalisation_Status__c,
                   Placeholder_All_In_Rate__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c = 'Draft'
            ORDER BY Period_Start__c ASC
        ]) {
            DraftRowDTO d = new DraftRowDTO();
            d.id                     = row.Id;
            d.periodStart            = row.Period_Start__c;
            d.periodEnd              = row.Period_End__c;
            d.dueDate                = row.Due_Date__c;
            d.principalDue           = row.Principal_Due__c;
            d.feesDue                = row.Fees_Due__c;
            d.rateFinalisationStatus = row.Rate_Finalisation_Status__c;
            d.placeholderAllInRate   = row.Placeholder_All_In_Rate__c;
            result.add(d);
        }
        return result;
    }

    @AuraEnabled
    public static void generateDraft(Id dpId) {
        try {
            PaymentScheduleService.generateDraft(dpId, UserInfo.getUserId());
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void submitForReview(Id dpId, String notes) {
        try {
            PaymentScheduleService.submitForReview(dpId, UserInfo.getUserId(), notes);
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void approve(Id dpId, String notes) {
        try {
            PaymentScheduleService.approve(dpId, UserInfo.getUserId(), notes);
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void reject(Id dpId, String reason) {
        try {
            PaymentScheduleService.reject(dpId, UserInfo.getUserId(), reason);
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public class StatusDTO {
        @AuraEnabled public Id dpId;
        @AuraEnabled public String dpName;
        @AuraEnabled public String dpStatus;
        @AuraEnabled public String scheduleGenerationStatus;
        @AuraEnabled public Id makerId;
        @AuraEnabled public String makerName;
        @AuraEnabled public Id checkerId;
        @AuraEnabled public String checkerName;
        @AuraEnabled public DateTime draftCreatedDateTime;
        @AuraEnabled public DateTime activatedDateTime;
        @AuraEnabled public String notes;
        @AuraEnabled public String lastRejectReason;
        @AuraEnabled public Id currentUserId;
        @AuraEnabled public List<String> preconditionFailures;
    }

    public class DraftRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal feesDue;
        @AuraEnabled public String rateFinalisationStatus;
        @AuraEnabled public Decimal placeholderAllInRate;
    }
}
