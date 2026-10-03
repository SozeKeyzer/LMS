/**
 * DebtPositionTriggerHandler
 * Phase 0: ProtectedFieldGuardHandler (via base) + audit trail.
 * Phase 1: In_Amendment flag management (via DebtPosition_StatusChange flow).
 * Schedule generation is exclusively a maker-checker action (PaymentScheduleService.
 * generateDraft/approve) — it is not triggered by Status transitions on this object.
 */
public class DebtPositionTriggerHandler extends LMSTriggerHandler {

    public DebtPositionTriggerHandler() {
        super('Debt_Position__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Debt_Position__c',
                String.valueOf(rec.Id), 'Debt Position created: ' + rec.get('Name'));
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            String newStatus = (String) newRec.get('Status__c');
            String oldStatus = (String) oldRec.get('Status__c');

            if (newStatus != oldStatus) {
                AuditEventLogger.logManual('STATUS_CHANGED', 'Debt_Position__c',
                    String.valueOf(newRec.Id),
                    'Debt Position status: ' + oldStatus + ' -> ' + newStatus);
            }
        }

        AuditEventLogger.flush();
    }
}