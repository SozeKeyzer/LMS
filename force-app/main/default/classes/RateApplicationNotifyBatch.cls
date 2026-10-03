/**
 * RateApplicationNotifyBatch — daily.
 * Finds Interest_Rate_Terms with Scheduled_Application_Date within 5 business days and notifies ops.
 */
public class RateApplicationNotifyBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date alertDate = Date.today().addDays(7); // approximate 5 business days
        return Database.getQueryLocator([
            SELECT Id, Application_Status__c, Scheduled_Application_Date__c
            FROM Interest_Rate_Terms__c
            WHERE Application_Status__c = 'Pending'
            AND Scheduled_Application_Date__c <= :alertDate
            AND Scheduled_Application_Date__c >= TODAY
        ]);
    }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject s : scope) {
            Interest_Rate_Terms__c irt = (Interest_Rate_Terms__c) s;
            AuditEventLogger.logEngine('RATE_APPLIED','Interest_Rate_Terms__c',
                String.valueOf(irt.Id),'Rate reset approaching: ' + irt.Scheduled_Application_Date__c);
        }
        AuditEventLogger.flush();
    }
    public void finish(Database.BatchableContext bc) {}
}