/**
 * RateFixingLockedStrategy
 * IRecalcStrategy for Trigger_Field__c = 'Rate_Fixing_Locked'.
 * When a Rate_Index_Fixing is ingested/locked, logs an audit event.
 * Full schedule-row update cascade requires Rate_Index→IRT→DP linkage
 * which is wired via MDT configuration in Phase 2+.
 * Spec v3 Part 10.1.
 *
 * recordId = Rate_Index_Fixing__c that has just been locked.
 */
public class RateFixingLockedStrategy implements IRecalcStrategy {

    public void execute(Id recordId, String correlationId) {
        Rate_Index_Fixing__c fixing = [
            SELECT Id, Fixing_Date__c, Rate__c, Rate_Index__c
            FROM Rate_Index_Fixing__c
            WHERE Id = :recordId
        ];

        AuditEventLogger.logEngine(
            'RATE_FIXING_LOCKED', 'Rate_Index_Fixing__c', String.valueOf(recordId),
            'Rate fixing ingested: rate=' + fixing.Rate__c + ' on ' + fixing.Fixing_Date__c
                + '. correlationId=' + correlationId
        );
        AuditEventLogger.flush();
    }
}