/**
 * AmortisationRulesTriggerHandler
 * Phase 0: wires ProtectedFieldGuardHandler (via LMSTriggerHandler base)
 * and logs key lifecycle events to Audit_Event__c.
 * Phase 1+ will add domain-specific methods here.
 */
public class AmortisationRulesTriggerHandler extends LMSTriggerHandler {

    public AmortisationRulesTriggerHandler() {
        super('Amortisation_Rules__c');
    }

    /** Log record creation to the audit trail. */
    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine(
                'RECORD_CREATED', 'Amortisation_Rules__c', String.valueOf(rec.Id),
                'Amortisation Rules record created: ' + rec.get('Name')
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