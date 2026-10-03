/**
 * RecalcCascadeService
 * Reads Recalc_Scope__mdt for a trigger event and executes the cascade.
 * Respects cross-tranche rules from Part 2.6.
 * Adding a new cascade = add one MDT record, zero code change here.
 * Spec v3 Part 10.
 *
 * R10 Source Guard: records where Source__c = 'System_Calculated' do NOT trigger
 * further cascades — prevents infinite loops from system-generated records.
 *
 * Each MDT record's Strategy_Class__c must implement IRecalcStrategy.
 * Strategies are instantiated via Type.forName() so no code change is needed
 * when a new cascade is added.
 */
public class RecalcCascadeService {

    /** Called from trigger handlers. source = the Source__c value of the triggering record. */
    public static void cascade(String triggerObject, String triggerField, String recordId) {
        cascade(triggerObject, triggerField, recordId, null);
    }

    public static void cascade(
        String triggerObject,
        String triggerField,
        String recordId,
        String source
    ) {
        // R10 Source Guard — system-generated records do not trigger cascades
        if (source == 'System_Calculated') return;

        List<Recalc_Scope__mdt> scopes = [
            SELECT Target_Object__c, Strategy_Class__c, Cascade_To_Children__c, Is_Active__c
            FROM Recalc_Scope__mdt
            WHERE Trigger_Object__c = :triggerObject
              AND Trigger_Field__c  = :triggerField
              AND Is_Active__c      = true
        ];
        if (scopes.isEmpty()) return;

        String corrId = CorrelationIdGenerator.generate();

        for (Recalc_Scope__mdt scope : scopes) {
            String strategyClass = scope.Strategy_Class__c;
            if (String.isBlank(strategyClass)) continue;

            Type stratType = Type.forName(strategyClass);
            if (stratType == null) {
                AuditEventLogger.logEngine(
                    'RECALC_CASCADE_ERROR', triggerObject, recordId,
                    'Strategy class not found: ' + strategyClass
                );
                continue;
            }

            IRecalcStrategy strategy = (IRecalcStrategy) stratType.newInstance();

            try {
                strategy.execute(Id.valueOf(recordId), corrId);
                AuditEventLogger.logEngine(
                    'RECALC_CASCADE', triggerObject, recordId,
                    'Cascade executed: ' + strategyClass + ' → ' + scope.Target_Object__c
                        + ' | correlationId=' + corrId
                );

                // Cascade to child tranches deferred (Tranche_Parent__c not deployed)
            } catch (Exception ex) {
                AuditEventLogger.logEngine(
                    'RECALC_CASCADE_ERROR', triggerObject, recordId,
                    'Strategy ' + strategyClass + ' threw: ' + ex.getMessage()
                );
            }
        }

        AuditEventLogger.flush();
    }

}