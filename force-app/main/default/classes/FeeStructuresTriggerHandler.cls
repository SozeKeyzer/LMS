/**
 * FeeStructuresTriggerHandler
 * Phase 0: wires ProtectedFieldGuardHandler (via LMSTriggerHandler base)
 * and logs key lifecycle events to Audit_Event__c.
 * Phase 1+ will add domain-specific methods here.
 */
public class FeeStructuresTriggerHandler extends LMSTriggerHandler {

    public FeeStructuresTriggerHandler() {
        super('Fee_Structures__c');
    }

    /** Log record creation to the audit trail. */
    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine(
                'RECORD_CREATED', 'Fee_Structures__c', String.valueOf(rec.Id),
                'Fee Structures record created: ' + rec.get('Name')
            );
        }
        AuditEventLogger.flush();
    }

    /** Log key field changes. ProtectedFieldGuardHandler already ran in base.run(). */
    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        AuditEventLogger.flush();
    }
}