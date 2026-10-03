/**
 * RateApplicationService
 * Apply / Defer / Waive workflows for Interest_Rate_Terms.
 * Writes Rate_Application_Event, updates IRT.Application_Status and Actual_Application_Date,
 * triggers recalc cascade via RecalcCascadeService.
 */
public class RateApplicationService {

    public static void applyDecision(Rate_Application_Event__c event) {
        Interest_Rate_Terms__c irt = [
            SELECT Id, Application_Status__c, Actual_Application_Date__c, Deferred_To_Date__c
            FROM Interest_Rate_Terms__c WHERE Id = :event.Interest_Rate_Terms__c FOR UPDATE
        ];

        switch on event.Decision_Type__c {
            when 'Apply' {
                irt.Application_Status__c      = 'Applied';
                irt.Actual_Application_Date__c = event.Decision_Date__c;
            }
            when 'Defer' {
                irt.Application_Status__c = 'Deferred';
                irt.Deferred_To_Date__c   = event.New_Application_Date__c;
            }
            when 'Waive_Period' {
                irt.Application_Status__c = 'Waived_For_Period';
            }
            when 'Waive_Permanently' {
                irt.Application_Status__c = 'Superseded';
            }
        }

        TriggerContext.getInstance().bypassGuards = true;
        update irt;
        TriggerContext.getInstance().bypassGuards = false;

        // Trigger recalc cascade if rate was applied
        if (event.Decision_Type__c == 'Apply') {
            RecalcCascadeService.cascade('Interest_Rate_Terms__c', 'Actual_Application_Date__c',
                String.valueOf(irt.Id));
        }

        AuditEventLogger.logManual('RATE_APPLIED', 'Interest_Rate_Terms__c',
            String.valueOf(irt.Id), 'Rate decision: ' + event.Decision_Type__c);
        AuditEventLogger.flush();
    }
}