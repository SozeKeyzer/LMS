/**
 * InterestPeriodHandler
 * Phase 1 trigger handler for Interest_Period__c.
 * Inherits ProtectedFieldGuardHandler.enforce() from LMSTriggerHandler base.
 */
public class InterestPeriodHandler extends LMSTriggerHandler {

    public InterestPeriodHandler() {
        super('Interest_Period__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Interest_Period__c',
                String.valueOf(rec.Id), 'Interest Period created.');
        }
        AuditEventLogger.flush();
        autoCreateElections(newList);
    }

    // For PIK Toggle DPs (PIK_Allowed + Borrower_Election mode), auto-create an open Election
    // record when a new Interest_Period is created so borrowers have a record to elect against.
    private static void autoCreateElections(List<SObject> newList) {
        Set<Id> dpIds = new Set<Id>();
        for (SObject rec : newList) dpIds.add((Id) rec.get('Debt_Position__c'));
        if (dpIds.isEmpty()) return;

        Map<Id, Debt_Position__c> dpMap = new Map<Id, Debt_Position__c>([
            SELECT Id, PIK_Allowed__c, PIK_Default_Mode__c
            FROM Debt_Position__c
            WHERE Id IN :dpIds
              AND PIK_Allowed__c = true
              AND PIK_Default_Mode__c = 'Elect'
        ]);
        if (dpMap.isEmpty()) return;

        List<Election__c> electionsToInsert = new List<Election__c>();
        for (SObject rec : newList) {
            Id dpId = (Id) rec.get('Debt_Position__c');
            if (!dpMap.containsKey(dpId)) continue;

            electionsToInsert.add(new Election__c(
                Debt_Position__c  = dpId,
                Period_Start__c   = (Date) rec.get('Period_Start__c'),
                Period_End__c     = (Date) rec.get('Period_End__c'),
                Election_Type__c  = 'Cash',       // open default; borrower may change before deadline
                Is_Immutable__c   = false,
                Default_Applied__c = false,
                Source__c         = 'System_Calculated',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
            ));
        }

        if (!electionsToInsert.isEmpty()) {
            TriggerContext.getInstance().bypassGuards = true;
            try {
                insert electionsToInsert;
            } finally {
                TriggerContext.getInstance().bypassGuards = false;
            }
        }
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            if (newRec.get('Status__c') != oldRec.get('Status__c')) {
                AuditEventLogger.logEngine('STATUS_CHANGED','Interest_Period__c',
                    String.valueOf(newRec.Id),'Period status: ' + newRec.get('Status__c'));
            }
        }
        AuditEventLogger.flush();
    }
}