/**
 * ElectionDeadlineBatch — daily batch that auto-defaults PIK elections past their deadline.
 * When a borrower has not locked an Election by Period_Start + PIK_Election_Deadline_Days,
 * ElectionService.applyDefault() is called which sets the DP's PIK_Default_Mode as the type.
 * Spec v3 Part 9.3 — borrower election workflow, default rule.
 */
public class ElectionDeadlineBatch implements Database.Batchable<SObject> {

    private Date runDate;

    public ElectionDeadlineBatch()           { this.runDate = Date.today(); }
    public ElectionDeadlineBatch(Date d)     { this.runDate = d; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Fetch all open elections — deadline arithmetic done in execute()
        // Include parent DP fields needed for applyDefault + deadline calculation
        return Database.getQueryLocator([
            SELECT Id, Election_Type__c, Cash_Amount__c, PIK_Amount__c,
                   Is_Immutable__c, Default_Applied__c, Period_Start__c, Debt_Position__c,
                   Debt_Position__r.PIK_Allowed__c,
                   Debt_Position__r.PIK_Default_Mode__c,
                   Debt_Position__r.PIK_Election_Deadline_Days__c
            FROM Election__c
            WHERE Is_Immutable__c = false
              AND Default_Applied__c = false
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Id> toDefault = new List<Id>();
        Map<Id, Debt_Position__c> dpMap = new Map<Id, Debt_Position__c>();

        for (SObject sobj : scope) {
            Election__c el = (Election__c) sobj;
            Decimal deadlineDays = el.Debt_Position__r.PIK_Election_Deadline_Days__c;
            if (deadlineDays == null || el.Period_Start__c == null) continue;

            Date deadline = el.Period_Start__c.addDays((Integer) deadlineDays);
            if (deadline > runDate) continue; // deadline not yet passed

            // Build a lightweight DP DTO to pass into applyDefault
            Debt_Position__c dp = new Debt_Position__c(
                Id                         = el.Debt_Position__c,
                PIK_Allowed__c             = el.Debt_Position__r.PIK_Allowed__c,
                PIK_Default_Mode__c        = el.Debt_Position__r.PIK_Default_Mode__c,
                PIK_Election_Deadline_Days__c = deadlineDays
            );
            dpMap.put(el.Id, dp);
            toDefault.add(el.Id);
        }

        if (toDefault.isEmpty()) return;

        // Re-query elections as updatable SObjects (relationship fields are read-only on scope records)
        List<Election__c> elections = [
            SELECT Id, Election_Type__c, Cash_Amount__c, PIK_Amount__c,
                   Is_Immutable__c, Default_Applied__c, Period_Start__c, Debt_Position__c
            FROM Election__c
            WHERE Id IN :toDefault
        ];

        for (Election__c el : elections) {
            Debt_Position__c dp = dpMap.get(el.Id);
            if (dp == null) continue;
            try {
                ElectionService.applyDefault(el, dp);
            } catch (Exception ex) {
                AuditEventLogger.logEngine('ELECTION_DEFAULTED','Election__c',
                    String.valueOf(el.Id), 'Auto-default failed: ' + ex.getMessage());
            }
        }
        AuditEventLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        AuditEventLogger.logEngine('ELECTION_PROCESSED','ElectionDeadlineBatch', null,
            'Election deadline batch completed for ' + runDate);
        AuditEventLogger.flush();
    }
}