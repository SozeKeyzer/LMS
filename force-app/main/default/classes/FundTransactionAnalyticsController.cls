public with sharing class FundTransactionAnalyticsController {

    // Parses "YYYY-M" month key (e.g. "2026-6") into a SOQL date function filter
    private static String monthFilter(String month) {
        if (String.isBlank(month)) return '';
        List<String> parts = month.split('-');
        if (parts.size() == 2 && parts[0].isNumeric() && parts[1].isNumeric()) {
            return ' AND CALENDAR_YEAR(Transaction_Date__c) = ' + Integer.valueOf(parts[0])
                 + ' AND CALENDAR_MONTH(Transaction_Date__c) = ' + Integer.valueOf(parts[1]);
        }
        return '';
    }

    @AuraEnabled
    public static List<AggregateResult> getFundFlowSummary(String month, String fundId) {
        String q = 'SELECT Fund__r.Name fundName, Fund__c fundId,'
                 + ' Transaction_Type__c txType, SUM(Amount__c) total,'
                 + ' COUNT(Id) txCount'
                 + ' FROM Fund_Transaction__c'
                 + ' WHERE Intrafund__c != true'
                 + ' AND Restricted_Entity__c != true';
        if (String.isNotBlank(fundId)) q += ' AND Fund__c = \'' + String.escapeSingleQuotes(fundId) + '\'';
        q += monthFilter(month);
        q += ' WITH USER_MODE'
           + ' GROUP BY Fund__r.Name, Fund__c, Transaction_Type__c'
           + ' ORDER BY Fund__r.Name, Transaction_Type__c';
        return Database.query(q);
    }

    @AuraEnabled
    public static List<AggregateResult> getBDMPerformance(String month, String fundId) {
        String q = 'SELECT BDM__r.Name bdmName, BDM__c bdmId,'
                 + ' Transaction_Type__c txType, SUM(Amount__c) total,'
                 + ' COUNT(Id) txCount'
                 + ' FROM Fund_Transaction__c'
                 + ' WHERE Intrafund__c != true'
                 + ' AND Restricted_Entity__c != true';
        if (String.isNotBlank(fundId)) q += ' AND Fund__c = \'' + String.escapeSingleQuotes(fundId) + '\'';
        q += monthFilter(month);
        q += ' WITH USER_MODE'
           + ' GROUP BY BDM__r.Name, BDM__c, Transaction_Type__c'
           + ' ORDER BY BDM__r.Name, Transaction_Type__c';
        return Database.query(q);
    }

    @AuraEnabled
    public static List<AggregateResult> getTransactionBreakdown(String fundId, String month) {
        String q = 'SELECT CALENDAR_YEAR(Transaction_Date__c) yr,'
                 + ' CALENDAR_MONTH(Transaction_Date__c) mo,'
                 + ' Transaction_Type__c txType,'
                 + ' SUM(Amount__c) total, COUNT(Id) txCount'
                 + ' FROM Fund_Transaction__c'
                 + ' WHERE Intrafund__c != true'
                 + ' AND Restricted_Entity__c != true'
                 + ' AND Transaction_Date__c != null';
        if (String.isNotBlank(fundId)) q += ' AND Fund__c = \'' + String.escapeSingleQuotes(fundId) + '\'';
        q += monthFilter(month);
        q += ' WITH USER_MODE'
           + ' GROUP BY CALENDAR_YEAR(Transaction_Date__c), CALENDAR_MONTH(Transaction_Date__c), Transaction_Type__c'
           + ' ORDER BY CALENDAR_YEAR(Transaction_Date__c) DESC, CALENDAR_MONTH(Transaction_Date__c) DESC, Transaction_Type__c';
        return Database.query(q);
    }

    @AuraEnabled
    public static List<AggregateResult> getSwitchFlowMap(String month, String fundId) {
        String q = 'SELECT Fund__r.Name fundName, Switched_From__r.Name switchedFrom,'
                 + ' Transaction_Type__c txType, SUM(Amount__c) total,'
                 + ' COUNT(Id) txCount'
                 + ' FROM Fund_Transaction__c'
                 + ' WHERE Transaction_Type__c IN (\'Fund Switch In\', \'Fund Switch Out\')'
                 + ' AND Restricted_Entity__c != true';
        if (String.isNotBlank(fundId)) q += ' AND Fund__c = \'' + String.escapeSingleQuotes(fundId) + '\'';
        q += monthFilter(month);
        q += ' WITH USER_MODE'
           + ' GROUP BY Fund__r.Name, Switched_From__r.Name, Transaction_Type__c'
           + ' ORDER BY Fund__r.Name';
        return Database.query(q);
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableMonths() {
        List<AggregateResult> rows = [
            SELECT CALENDAR_YEAR(Transaction_Date__c) yr, CALENDAR_MONTH(Transaction_Date__c) mo
            FROM Fund_Transaction__c
            WHERE Transaction_Date__c != null
            WITH USER_MODE
            GROUP BY CALENDAR_YEAR(Transaction_Date__c), CALENDAR_MONTH(Transaction_Date__c)
            ORDER BY CALENDAR_YEAR(Transaction_Date__c), CALENDAR_MONTH(Transaction_Date__c)
        ];
        List<String> months = new List<String>();
        for (AggregateResult ar : rows) {
            months.add(String.valueOf((Integer) ar.get('yr')) + '-' + String.valueOf((Integer) ar.get('mo')));
        }
        return months;
    }
}
