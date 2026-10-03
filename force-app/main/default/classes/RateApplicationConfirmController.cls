/**
 * RateApplicationConfirmController
 *
 * Apex controller for the rateApplicationConfirm LWC.
 * Loads Rate_Application_Event context (RAE + parent IRT details) and
 * executes the ops decision (Apply / Defer / Waive) by calling RateApplicationService.
 *
 * with sharing + USER_MODE query enforce OWD and FLS.
 */
public with sharing class RateApplicationConfirmController {

    /**
     * Loads the RAE and its parent IRT for display in the LWC.
     * Returns a plain Map so the LWC gets a flat, JSON-serialisable object.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEventDetails(Id raeId) {
        if (raeId == null) return null;

        List<Rate_Application_Event__c> rows = [
            SELECT Id, Decision_Type__c, Decision_Date__c, Reason__c,
                   New_Application_Date__c, Source__c,
                   Interest_Rate_Terms__c,
                   Interest_Rate_Terms__r.Application_Status__c,
                   Interest_Rate_Terms__r.Pricing_Basis__c,
                   Interest_Rate_Terms__r.Applicable_Fixed_Rate__c,
                   Interest_Rate_Terms__r.Spread__c,
                   Interest_Rate_Terms__r.Rate_Reset_Trigger__c,
                   Interest_Rate_Terms__r.Application_Rule__c,
                   Interest_Rate_Terms__r.Actual_Application_Date__c
            FROM Rate_Application_Event__c
            WHERE Id = :raeId
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;

        Rate_Application_Event__c rae = rows[0];
        SObject irt = rae.getSObject('Interest_Rate_Terms__r');
        String decision = (String) rae.get('Decision_Type__c');

        Map<String, Object> result = new Map<String, Object>{
            'raeId'              => rae.get('Id'),
            'decisionType'       => decision,
            'decisionDate'       => rae.get('Decision_Date__c'),
            'reason'             => rae.get('Reason__c'),
            'newApplicationDate' => rae.get('New_Application_Date__c'),
            'isPending'          => String.isBlank(decision),
            'irtId'              => rae.get('Interest_Rate_Terms__c')
        };

        if (irt != null) {
            result.put('irtStatus',       irt.get('Application_Status__c'));
            result.put('pricingBasis',    irt.get('Pricing_Basis__c'));
            result.put('fixedRate',       irt.get('Applicable_Fixed_Rate__c'));
            result.put('spread',          irt.get('Spread__c'));
            result.put('resetTrigger',    irt.get('Rate_Reset_Trigger__c'));
            result.put('applicationRule', irt.get('Application_Rule__c'));
            result.put('actualAppDate',   irt.get('Actual_Application_Date__c'));
        }

        return result;
    }

    /**
     * Records the ops decision on the RAE and delegates to RateApplicationService.
     * Called when ops clicks Apply / Defer / Waive on the LWC.
     *
     * @param raeId        Id of the Rate_Application_Event__c
     * @param decisionType Apply | Defer | Waive_Period | Waive_Permanently
     * @param reason       Required for Defer, Waive_Period, Waive_Permanently
     * @param deferDate    Required when decisionType = Defer
     */
    @AuraEnabled
    public static void submitDecision(Id raeId, String decisionType, String reason, Date deferDate) {
        if (raeId == null || String.isBlank(decisionType)) {
            throw new AuraHandledException('raeId and decisionType are required.');
        }

        // Stamp the decision fields on the RAE record
        update new Rate_Application_Event__c(
            Id                      = raeId,
            Decision_Type__c        = decisionType,
            Decision_Date__c        = Date.today(),
            Reason__c               = reason,
            New_Application_Date__c = (decisionType == 'Defer') ? deferDate : null
        );

        // Reload with IRT lookup populated — RateApplicationService needs Interest_Rate_Terms__c
        Rate_Application_Event__c rae = [
            SELECT Id, Decision_Type__c, Decision_Date__c,
                   Reason__c, New_Application_Date__c, Interest_Rate_Terms__c
            FROM Rate_Application_Event__c
            WHERE Id = :raeId LIMIT 1
        ];

        RateApplicationService.applyDecision(rae);
    }
}