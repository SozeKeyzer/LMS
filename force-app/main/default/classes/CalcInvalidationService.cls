public with sharing class CalcInvalidationService {

    /**
     * Called by CalculationOrchestrator after a successful Commit.
     * Marks the most recent Calculation_Run for each downstream calc as Stale
     * by updating a custom field — CalcReadinessController reads this to show
     * the Stale badge without any extra objects.
     *
     * Stale detection in CalcReadinessController: if the most recent run for
     * a calc has Run_At__c earlier than the parent's LastModifiedDate, it's Stale.
     * This method forces a "touch" on those runs to reset the comparison baseline.
     * Actually we mark them by setting Error_Message__c to a sentinel so the
     * readiness controller can detect staleness without an extra field.
     *
     * Simpler approach: flagStale stores which (calcName, parentId) pairs are stale
     * in a static set that persists for the transaction. CalcReadinessController
     * checks LastModifiedDate vs Run_At__c independently per query.
     */
    private static Map<String, Set<Id>> staleMap = new Map<String, Set<Id>>();

    public static void flagStale(String invalidatesField, Id parentId) {
        if (String.isBlank(invalidatesField)) return;
        for (String calcName : invalidatesField.split(',')) {
            String key = calcName.trim();
            if (!staleMap.containsKey(key)) {
                staleMap.put(key, new Set<Id>());
            }
            staleMap.get(key).add(parentId);
        }
    }

    public static Boolean isStale(String calcDeveloperName, Id parentId) {
        Set<Id> parents = staleMap.get(calcDeveloperName);
        return parents != null && parents.contains(parentId);
    }

    public static void markOutputsStale(String objectApiName, Id parentId) {
        try {
            String soql = 'SELECT Id FROM ' + objectApiName
                        + ' WHERE Debt_Position__c = :parentId LIMIT 200';
            List<SObject> records = Database.query(soql);
            List<SObject> toUpdate = new List<SObject>();
            for (SObject rec : records) {
                SObject updated = rec.getSObjectType().newSObject(rec.Id);
                try {
                    updated.put('Locked_By_Manual_Mode__c', false);
                    toUpdate.add(updated);
                } catch (Exception e) {}
            }
            if (!toUpdate.isEmpty()) update toUpdate;
        } catch (Exception e) {
            System.debug('CalcInvalidationService.markOutputsStale: ' + e.getMessage());
        }
    }
}