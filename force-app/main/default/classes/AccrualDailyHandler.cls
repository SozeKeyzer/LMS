/**
 * AccrualDailyHandler
 * Phase 0 trigger handler for Accrual_Daily__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class AccrualDailyHandler extends LMSTriggerHandler {

    public AccrualDailyHandler() {
        super('Accrual_Daily__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Accrual_Daily__c',
                String.valueOf(rec.Id), 'Accrual Daily created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('ACCRUAL_POSTED','Accrual_Daily__c',
                String.valueOf(rec.Id),'Accrual updated.');
        }
        AuditEventLogger.flush();
    }
}