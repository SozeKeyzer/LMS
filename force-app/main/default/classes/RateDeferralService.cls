/**
 * RateDeferralService
 * Phase 2: full rate deferral/waiver workflow.
 * Creates Rate_Application_Event records and updates IRT Application_Status.
 * Called by RateDeferral_Screen flow via @InvocableMethod.
 */
public class RateDeferralService {

    @InvocableMethod(label='Apply Rate Decision' category='LMS'
        description='Apply, defer, waive, or reinstate an Interest_Rate_Terms rate application.')
    public static void applyDecision(List<RateDeferralRequest> requests) {
        List<Rate_Application_Event__c> eventsToInsert = new List<Rate_Application_Event__c>();
        List<Interest_Rate_Terms__c> irtsToUpdate = new List<Interest_Rate_Terms__c>();
        String corrId = TriggerContext.getInstance().correlationId;

        for (RateDeferralRequest req : requests) {
            // Build Rate_Application_Event
            Rate_Application_Event__c evt = new Rate_Application_Event__c(
                Interest_Rate_Terms__c   = req.interestRateTermsId,
                Decision_Date__c         = req.decisionDate != null ? req.decisionDate : Date.today(),
                Decision_Type__c         = req.decisionType,
                New_Application_Date__c  = req.newApplicationDate,
                Reason__c                = req.reason,
                Correlation_Id__c        = corrId,
                Source__c                = 'Manual_Entry'
            );
            eventsToInsert.add(evt);

            // Build IRT status update
            Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(Id = req.interestRateTermsId);
            switch on req.decisionType {
                when 'Apply' {
                    irt.Application_Status__c      = 'Applied';
                    irt.Actual_Application_Date__c = req.decisionDate != null ? req.decisionDate : Date.today();
                }
                when 'Defer' {
                    irt.Application_Status__c    = 'Deferred';
                    irt.Deferred_To_Date__c      = req.newApplicationDate;
                    irt.Deferral_Reason__c        = req.reason;
                    irt.Deferral_Review_Date__c   = req.reviewDate;
                    irt.Deferral_Approved_Date__c = req.decisionDate;
                }
                when 'Waive_Period' {
                    irt.Application_Status__c = 'Waived_For_Period';
                }
                when 'Waive_Permanently' {
                    irt.Application_Status__c = 'Superseded';
                }
            }
            irtsToUpdate.add(irt);
        }

        TriggerContext.getInstance().bypassGuards = true;
        if (!eventsToInsert.isEmpty()) insert eventsToInsert;
        if (!irtsToUpdate.isEmpty()) update irtsToUpdate;
        TriggerContext.getInstance().bypassGuards = false;

        for (RateDeferralRequest req : requests) {
            AuditEventLogger.logManual('RATE_APPLIED','Interest_Rate_Terms__c',
                String.valueOf(req.interestRateTermsId),'Rate decision: ' + req.decisionType + ' | ' + req.reason);
        }
        AuditEventLogger.flush();
    }

    public class RateDeferralRequest {
        @InvocableVariable(required=true  label='Interest Rate Terms ID') public Id     interestRateTermsId;
        @InvocableVariable(required=true  label='Decision Type')          public String decisionType;
        @InvocableVariable(required=false label='Decision Date')          public Date   decisionDate;
        @InvocableVariable(required=false label='New Application Date')   public Date   newApplicationDate;
        @InvocableVariable(required=false label='Deferral Review Date')   public Date   reviewDate;
        @InvocableVariable(required=true  label='Reason')                 public String reason;
    }
}