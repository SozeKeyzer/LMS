/**
 * FinancialInstrumentTriggerHandler
 * Phase 0: wires ProtectedFieldGuardHandler (via LMSTriggerHandler base)
 * and logs key lifecycle events to Audit_Event__c.
 * Phase 1+ will add domain-specific methods here.
 */
public class FinancialInstrumentTriggerHandler extends LMSTriggerHandler {

    public FinancialInstrumentTriggerHandler() {
        super('Financial_Instrument__c');
    }

    /** Log record creation to the audit trail. */
    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine(
                'RECORD_CREATED', 'Financial_Instrument__c', String.valueOf(rec.Id),
                'Financial Instrument record created: ' + rec.get('Name')
            );
        }
        AuditEventLogger.flush();
    }

    /** Log status/key field changes. ProtectedFieldGuardHandler already ran in base.run(). */
    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            Object newStatus = newRec.get('Status__c');
            Object oldStatus = oldRec != null ? oldRec.get('Status__c') : null;
            if (newStatus != null && newStatus != oldStatus) {
                AuditEventLogger.logManual(
                    'STATUS_CHANGED', 'Financial_Instrument__c', String.valueOf(newRec.Id),
                    'Financial Instrument status changed: ' + oldStatus + ' → ' + newStatus
                );
            }
        }
        AuditEventLogger.flush();
    }
}
