/**
 * ProtectedFieldGuardHandler
 * Reads Protected_Field__mdt at runtime and blocks direct edits to guarded fields.
 * Called from every trigger handler in the UPDATE path.
 * Caches MDT records once per transaction — never hits SOQL inside loops.
 */
public class ProtectedFieldGuardHandler {

    // Per-transaction cache: object API name → list of protection rules
    private static Map<String, List<Protected_Field__mdt>> ruleCache;

    private static Map<String, List<Protected_Field__mdt>> getRules() {
        if (ruleCache == null) {
            ruleCache = new Map<String, List<Protected_Field__mdt>>();
            for (Protected_Field__mdt rule : [
                SELECT Object_API_Name__c, Field_API_Name__c, Protection_Rule__c, Error_Message__c
                FROM Protected_Field__mdt
            ]) {
                String key = rule.Object_API_Name__c;
                if (!ruleCache.containsKey(key)) {
                    ruleCache.put(key, new List<Protected_Field__mdt>());
                }
                ruleCache.get(key).add(rule);
            }
        }
        return ruleCache;
    }

    /**
     * Call this from trigger handlers on BEFORE UPDATE.
     * @param objectApiName  API name of the object being updated
     * @param newList        Trigger.new
     * @param oldMap         Trigger.oldMap
     */
    public static void enforce(
        String objectApiName,
        List<SObject> newList,
        Map<Id, SObject> oldMap
    ) {
        // Bypass for engine recalculations that have authority to update protected fields
        if (TriggerContext.getInstance().bypassGuards) return;

        Map<String, List<Protected_Field__mdt>> allRules = getRules();
        if (!allRules.containsKey(objectApiName)) return;

        List<Protected_Field__mdt> rules = allRules.get(objectApiName);

        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (oldRec == null) continue;

            for (Protected_Field__mdt rule : rules) {
                Object newVal = newRec.get(rule.Field_API_Name__c);
                Object oldVal = oldRec.get(rule.Field_API_Name__c);

                // No change — nothing to block
                if (newVal == oldVal) continue;
                if (newVal == null && oldVal == null) continue;

                Boolean shouldBlock = false;

                switch on rule.Protection_Rule__c {
                    when 'Always' {
                        shouldBlock = true;
                    }
                    when 'When_Immutable' {
                        Object immutable = oldRec.get('Is_Immutable__c');
                        shouldBlock = (immutable == true);
                    }
                    when 'When_In_Amendment' {
                        Object inAmend = oldRec.get('In_Amendment__c');
                        shouldBlock = (inAmend == true);
                    }
                }

                if (shouldBlock) {
                    String msg = String.isNotBlank(rule.Error_Message__c)
                        ? rule.Error_Message__c
                        : 'Field ' + rule.Field_API_Name__c + ' is protected and cannot be modified directly.';
                    newRec.addError(msg);

                    // Log the blocked attempt — flush after loop
                    AuditEventLogger.log(
                        'GUARD_VIOLATION_BLOCKED',
                        objectApiName,
                        String.valueOf(newRec.Id),
                        'System_Calculated',
                        'Blocked modification of protected field: ' + rule.Field_API_Name__c +
                            ' | Old: ' + oldVal + ' | Attempted: ' + newVal,
                        String.valueOf(oldVal),
                        String.valueOf(newVal)
                    );
                }
            }
        }
        AuditEventLogger.flush();
    }

    /** Clears the rule cache — call in @TestSetup to ensure fresh MDT data. */
    @TestVisible
    public static void clearCache() { ruleCache = null; }
}
