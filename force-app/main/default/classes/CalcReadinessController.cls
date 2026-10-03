public with sharing class CalcReadinessController {

    @AuraEnabled(cacheable=true)
    public static List<ReadinessDTO> getReadiness(Id recordId, String objectApiName) {
        List<ReadinessDTO> result = new List<ReadinessDTO>();

        List<Calculation_Definition__mdt> defs = [
            SELECT DeveloperName, MasterLabel, Description__c, Input_Fields__c,
                   Mode__c, Lifecycle_State__c, Version__c, Trigger_Event__c
            FROM Calculation_Definition__mdt
            WHERE Trigger_Object__c = :objectApiName
              AND Active__c = true
              AND Lifecycle_State__c = 'Locked'
        ];

        // Query parent LastModifiedDate for stale detection
        Datetime parentLastModified = null;
        try {
            String lmSoql = 'SELECT LastModifiedDate FROM ' + objectApiName
                          + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> parents = Database.query(lmSoql);
            if (!parents.isEmpty()) {
                parentLastModified = (Datetime) parents[0].get('LastModifiedDate');
            }
        } catch (Exception e) {}

        // Most recent successful run per calc for this record
        Map<String, Datetime> lastRunAt = new Map<String, Datetime>();
        List<Calculation_Run__c> runs = [
            SELECT Calc_Definition__c, Run_At__c
            FROM Calculation_Run__c
            WHERE (Debt_Position__c = :recordId OR Financial_Instrument__c = :recordId)
              AND Run_Mode__c = 'Commit'
              AND Status__c = 'Success'
            ORDER BY Run_At__c DESC
            LIMIT 200
        ];
        for (Calculation_Run__c r : runs) {
            if (!lastRunAt.containsKey(r.Calc_Definition__c)) {
                lastRunAt.put(r.Calc_Definition__c, r.Run_At__c);
            }
        }

        for (Calculation_Definition__mdt def : defs) {
            ReadinessDTO dto = new ReadinessDTO();
            dto.calcDeveloperName = def.DeveloperName;
            dto.calcName          = def.MasterLabel;
            dto.description       = def.Description__c;
            dto.mode              = def.Mode__c;
            dto.version           = def.Version__c;
            dto.triggerEvent      = def.Trigger_Event__c;
            dto.missingFields     = new List<String>();

            if (String.isNotBlank(def.Input_Fields__c)) {
                try {
                    List<Object> inputs = (List<Object>) JSON.deserializeUntyped(def.Input_Fields__c);
                    Map<String, String> requiredFields = new Map<String, String>();
                    List<Map<String, Object>> childChecks = new List<Map<String, Object>>();

                    for (Object o : inputs) {
                        Map<String, Object> inp = (Map<String, Object>) o;
                        if (inp.get('required') == true) {
                            if ('childRecord'.equals(String.valueOf(inp.get('type')))) {
                                childChecks.add(inp);
                            } else {
                                requiredFields.put(
                                    (String) inp.get('apiName'),
                                    (String) inp.get('label')
                                );
                            }
                        }
                    }

                    if (!requiredFields.isEmpty()) {
                        String fieldList = String.join(new List<String>(requiredFields.keySet()), ',');
                        String soql = 'SELECT ' + fieldList
                            + ' FROM ' + objectApiName
                            + ' WHERE Id = :recordId LIMIT 1';
                        List<SObject> records = Database.query(soql);
                        if (!records.isEmpty()) {
                            SObject rec = records[0];
                            for (String apiName : requiredFields.keySet()) {
                                Object val = rec.get(apiName);
                                if (val == null || String.valueOf(val).trim() == '') {
                                    dto.missingFields.add(requiredFields.get(apiName));
                                }
                            }
                        }
                    }

                    for (Map<String, Object> check : childChecks) {
                        String childObject = (String) check.get('objectApiName');
                        String parentField = (String) check.get('parentField');
                        String extraFilter = (String) check.get('filter');
                        String label       = (String) check.get('label');
                        String countSoql = 'SELECT COUNT() FROM ' + childObject
                            + ' WHERE ' + parentField + ' = :recordId';
                        if (String.isNotBlank(extraFilter)) {
                            countSoql += ' AND ' + extraFilter;
                        }
                        if (Database.countQuery(countSoql) == 0) {
                            dto.missingFields.add(label);
                        }
                    }
                } catch (Exception e) {}
            }

            if (!dto.missingFields.isEmpty()) {
                dto.status = 'Blocked';
            } else if (isStale(def.DeveloperName, lastRunAt, parentLastModified)) {
                dto.status = 'Stale';
            } else {
                dto.status = 'Ready';
            }

            result.add(dto);
        }
        return result;
    }

    // A calc is Stale if it has been run before AND the parent was modified after that run
    private static Boolean isStale(String calcName, Map<String, Datetime> lastRunAt,
                                    Datetime parentLastModified) {
        if (!lastRunAt.containsKey(calcName)) return false;
        if (parentLastModified == null) return false;
        return parentLastModified > lastRunAt.get(calcName);
    }

    @AuraEnabled
    public static String preview(String calcDeveloperName, Id recordId) {
        return JSON.serialize(CalculationOrchestrator.run(calcDeveloperName, recordId, 'Preview'));
    }

    @AuraEnabled
    public static String generate(String calcDeveloperName, Id recordId) {
        return JSON.serialize(CalculationOrchestrator.run(calcDeveloperName, recordId, 'Commit'));
    }

    public class ReadinessDTO {
        @AuraEnabled public String calcDeveloperName;
        @AuraEnabled public String calcName;
        @AuraEnabled public String description;
        @AuraEnabled public String mode;
        @AuraEnabled public String triggerEvent;
        @AuraEnabled public String version;
        @AuraEnabled public String status;
        @AuraEnabled public List<String> missingFields;
    }
}