/**
 * LoanAmendmentHandler
 * Trigger handler for Loan_Amendment__c.
 */
public class LoanAmendmentHandler extends LMSTriggerHandler {

    public LoanAmendmentHandler() {
        super('Loan_Amendment__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        Set<Id> dpIds = new Set<Id>();
        Set<Id> fiIds = new Set<Id>();
        for (SObject rec : newList) {
            AuditEventLogger.logManual('AMENDMENT_DRAFTED', 'Loan_Amendment__c',
                String.valueOf(rec.Id), 'Loan Amendment created.');
            Id dpId = (Id) rec.get('Debt_Position__c');
            Id fiId = (Id) rec.get('Financial_Instrument__c');
            if (dpId != null) dpIds.add(dpId);
            if (fiId != null) fiIds.add(fiId);
        }
        TriggerContext.getInstance().bypassGuards = true;
        try {
            if (!dpIds.isEmpty()) {
                List<Debt_Position__c> dpUpdates = new List<Debt_Position__c>();
                for (Id dpId : dpIds) dpUpdates.add(new Debt_Position__c(Id = dpId, In_Amendment__c = true));
                update dpUpdates;
            }
            if (!fiIds.isEmpty()) {
                List<Financial_Instrument__c> fiUpdates = new List<Financial_Instrument__c>();
                for (Id fiId : fiIds) fiUpdates.add(new Financial_Instrument__c(Id = fiId, In_Amendment__c = true));
                update fiUpdates;
            }
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }
        AuditEventLogger.flush();
    }

    // Sets Actual_Effective_Date__c and captures Before_State__c snapshot in before-update
    // context so the state is recorded before any commit DML runs in afterUpdate.
    override protected void beforeUpdate(List<SObject> newList, Map<Id,SObject> oldMap) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') == 'Effective' &&
                oldRec.get('Status__c') != 'Effective') {
                Loan_Amendment__c la = (Loan_Amendment__c) newRec;
                la.Actual_Effective_Date__c = Date.today();
                la.Before_State__c          = AmendmentService.captureBeforeState(la);
            }
        }
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') == 'Effective' &&
                oldRec.get('Status__c') != 'Effective') {
                AmendmentService.executeCommit((Loan_Amendment__c) newRec);
            }
        }
    }
}