/**
 * StatusIndicatorController
 *
 * Drives the recordStatusIndicators LWC. Reads Status_Indicator__mdt rows
 * for a given parent object, runs the configured query (count or latest),
 * and returns active indicators only.
 *
 * Security:
 *   - with sharing enforces record-level OWD/sharing.
 *   - AccessLevel.USER_MODE on every Database.queryWithBinds / countQueryWithBinds
 *     enforces FLS and sharing at the query layer.
 *   - Object + field existence checked via Schema describe before query execution.
 *   - Filter strings validated via regex to reject SOQL injection patterns.
 *
 * Requirements: API version 60.0+ (Database.queryWithBinds / countQueryWithBinds
 * with AccessLevel were introduced in API v57).
 */
public with sharing class StatusIndicatorController {

    /**
     * SAFE_FILTER — whitelist of characters permitted in Active_Filter__c fragments.
     *
     * Allows: letters, digits, underscore, whitespace, parentheses, dot, comma,
     * single-quote (for string literals), comparison operators, dash, colon.
     * Rejects: semicolons, subquery keywords, and anything outside the set.
     *
     * Bug fix vs spec: the original pattern string used \\\\ followed by a bare
     * single-quote which terminates the Apex string literal prematurely (syntax error).
     * Corrected to \' so the quote is an escaped character inside the string.
     */
    @TestVisible
    private static final Pattern SAFE_FILTER = Pattern.compile(
        '^[A-Za-z0-9_\\s\\(\\)\\.,\'><=!\\-:]+$'
    );

    // -------------------------------------------------------------------------
    // Public wire-service method
    // -------------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static List<IndicatorResult> getIndicators(
        Id recordId,
        String parentObjectApiName
    ) {
        if (recordId == null || String.isBlank(parentObjectApiName)) {
            return new List<IndicatorResult>();
        }

        List<Status_Indicator__mdt> configs = [
            SELECT DeveloperName, Label__c, Parent_Object__c, Child_Object__c,
                   Relationship_Field__c, Active_Filter__c, Indicator_Mode__c,
                   Latest_Sort_Field__c, Latest_Display_Field__c,
                   Icon__c, Variant__c, Detail_Template__c,
                   Related_List_API_Name__c, Sort_Order__c, Is_Active__c
            FROM Status_Indicator__mdt
            WHERE Parent_Object__c = :parentObjectApiName
              AND Is_Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];

        List<IndicatorResult> results = new List<IndicatorResult>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        for (Status_Indicator__mdt cfg : configs) {
            try {
                IndicatorResult r = evaluate(cfg, recordId, gd);
                if (r != null && r.hasRecords) {
                    results.add(r);
                }
            } catch (Exception e) {
                // Bad CMDT config or runtime error — skip this indicator silently.
                // Logged for admin debugging; never surfaced to the UI.
                System.debug(LoggingLevel.WARN,
                    'StatusIndicator skipped [' + cfg.DeveloperName + ']: ' + e.getMessage());
            }
        }

        return results;
    }

    // -------------------------------------------------------------------------
    // Private evaluation methods
    // -------------------------------------------------------------------------

    private static IndicatorResult evaluate(
        Status_Indicator__mdt cfg, Id recordId,
        Map<String, Schema.SObjectType> gd
    ) {
        // 1. Child object must exist and be accessible to the running user
        Schema.SObjectType sot = gd.get(cfg.Child_Object__c);
        if (sot == null) return null;

        Schema.DescribeSObjectResult dsr = sot.getDescribe();
        if (!dsr.isAccessible()) return null;

        // 2. Relationship field must exist on the child object.
        //    Field-map keys are always lowercase in Salesforce describe results.
        //    Bug fix vs spec: original used raw cfg.Relationship_Field__c without
        //    toLowerCase(), causing containsKey() to return false for any field.
        Map<String, Schema.SObjectField> fieldMap = dsr.fields.getMap();
        if (!fieldMap.containsKey(cfg.Relationship_Field__c.toLowerCase())) {
            System.debug(LoggingLevel.WARN,
                'StatusIndicator [' + cfg.DeveloperName + ']: Relationship_Field__c ' +
                cfg.Relationship_Field__c + ' not found on ' + cfg.Child_Object__c);
            return null;
        }

        // 3. Validate the filter fragment — reject injection patterns
        String filter = cfg.Active_Filter__c == null ? '' : cfg.Active_Filter__c.trim();
        if (String.isNotBlank(filter)) {
            // Extra keyword checks on top of the character whitelist
            String filterUpper = filter.toUpperCase();
            if (filterUpper.contains(';') ||
                filterUpper.contains('SELECT') ||
                filterUpper.contains('DELETE') ||
                filterUpper.contains('UPDATE') ||
                filterUpper.contains('INSERT')) {
                System.debug(LoggingLevel.WARN,
                    'StatusIndicator [' + cfg.DeveloperName + ']: rejected dangerous filter');
                return null;
            }
            if (!SAFE_FILTER.matcher(filter).matches()) {
                System.debug(LoggingLevel.WARN,
                    'StatusIndicator [' + cfg.DeveloperName + ']: filter failed character whitelist');
                return null;
            }
        }

        if (cfg.Indicator_Mode__c == 'Latest_Record') {
            return evaluateLatest(cfg, recordId, filter, fieldMap);
        }
        return evaluateCount(cfg, recordId, filter);
    }

    @TestVisible
    private static IndicatorResult evaluateCount(
        Status_Indicator__mdt cfg, Id recordId, String filter
    ) {
        // Bug fix vs spec: original appended ' WITH USER_MODE' to the SOQL string.
        // When using Database.countQueryWithBinds(..., AccessLevel.USER_MODE), the
        // AccessLevel parameter IS the enforcement mechanism — adding WITH USER_MODE
        // inside the string as well causes a duplicate/conflicting directive.
        // Removed from string; AccessLevel.USER_MODE on the method call is sufficient.
        String soql =
            'SELECT COUNT() FROM ' + cfg.Child_Object__c +
            ' WHERE ' + cfg.Relationship_Field__c + ' = :recordId';
        if (String.isNotBlank(filter)) {
            soql += ' AND (' + filter + ')';
        }

        Integer cnt = Database.countQueryWithBinds(
            soql,
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );

        IndicatorResult r = baseResult(cfg);
        r.hasRecords = cnt > 0;
        r.count      = cnt;
        r.detail     = renderDetail(cfg.Detail_Template__c, cnt, null);
        return r;
    }

    @TestVisible
    private static IndicatorResult evaluateLatest(
        Status_Indicator__mdt cfg, Id recordId, String filter,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (String.isBlank(cfg.Latest_Sort_Field__c) ||
            String.isBlank(cfg.Latest_Display_Field__c)) {
            System.debug(LoggingLevel.WARN,
                'StatusIndicator [' + cfg.DeveloperName +
                ']: Latest_Record mode requires Latest_Sort_Field__c and Latest_Display_Field__c');
            return null;
        }

        // Validate sort and display fields exist on the child object
        if (!fieldMap.containsKey(cfg.Latest_Sort_Field__c.toLowerCase()) ||
            !fieldMap.containsKey(cfg.Latest_Display_Field__c.toLowerCase())) {
            System.debug(LoggingLevel.WARN,
                'StatusIndicator [' + cfg.DeveloperName + ']: sort/display field not found');
            return null;
        }

        // Build a deduplicated SELECT list to avoid SOQL error when sort == display field
        // Bug fix vs spec: original SELECT used both fields unconditionally, producing
        // "SELECT Id, Name, X, X FROM ..." which Salesforce rejects.
        List<String> selectFields = new List<String>{ 'Id', 'Name' };
        String sortFld    = cfg.Latest_Sort_Field__c.toLowerCase();
        String displayFld = cfg.Latest_Display_Field__c.toLowerCase();
        if (sortFld != 'id' && sortFld != 'name') {
            selectFields.add(cfg.Latest_Sort_Field__c);
        }
        if (displayFld != 'id' && displayFld != 'name' && displayFld != sortFld) {
            selectFields.add(cfg.Latest_Display_Field__c);
        }

        // Bug fix vs spec: original had WITH USER_MODE after LIMIT 1 which is invalid SOQL
        // (WITH must precede ORDER BY/LIMIT). Removed entirely — AccessLevel.USER_MODE
        // on Database.queryWithBinds handles enforcement.
        String soql =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + cfg.Child_Object__c +
            ' WHERE ' + cfg.Relationship_Field__c + ' = :recordId';
        if (String.isNotBlank(filter)) {
            soql += ' AND (' + filter + ')';
        }
        soql += ' ORDER BY ' + cfg.Latest_Sort_Field__c + ' DESC NULLS LAST LIMIT 1';

        List<SObject> rows = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );

        IndicatorResult r = baseResult(cfg);
        if (rows.isEmpty()) {
            r.hasRecords = false;
            return r;
        }

        SObject row = rows[0];
        r.hasRecords  = true;
        r.recordId    = (Id) row.get('Id');
        r.statusValue = String.valueOf(row.get(cfg.Latest_Display_Field__c));

        Object sortVal = row.get(cfg.Latest_Sort_Field__c);
        r.detail = renderDetail(cfg.Detail_Template__c, 1,
                                sortVal != null ? String.valueOf(sortVal) : null);
        return r;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static IndicatorResult baseResult(Status_Indicator__mdt cfg) {
        IndicatorResult r    = new IndicatorResult();
        r.developerName      = cfg.DeveloperName;
        r.label              = cfg.Label__c;
        r.icon               = cfg.Icon__c;
        r.variant            = cfg.Variant__c;
        r.mode               = cfg.Indicator_Mode__c;
        r.relatedListName    = cfg.Related_List_API_Name__c;
        return r;
    }

    private static String renderDetail(String tpl, Integer count, String sortVal) {
        if (String.isBlank(tpl)) return null;
        String out = tpl.replace('{!Count}', String.valueOf(count));
        if (String.isNotBlank(sortVal)) {
            out = out.replace('{!SortValue}', sortVal);
        }
        return out;
    }

    // -------------------------------------------------------------------------
    // DTO — serialised to JSON by the wire service
    // -------------------------------------------------------------------------

    public class IndicatorResult {
        @AuraEnabled public String  developerName;
        @AuraEnabled public String  label;
        @AuraEnabled public String  icon;
        @AuraEnabled public String  variant;
        @AuraEnabled public String  mode;
        @AuraEnabled public Boolean hasRecords    = false;
        @AuraEnabled public Integer count         = 0;
        @AuraEnabled public String  statusValue;
        @AuraEnabled public String  detail;
        @AuraEnabled public Id      recordId;
        @AuraEnabled public String  relatedListName;
    }
}
