/**
 * DrawdownRequestHandler
 * Phase 2 trigger handler for Drawdown_Request__c.
 * afterUpdate: when Status = Funded, calls DisbursementService.createForDrawdown.
 */
public class DrawdownRequestHandler extends LMSTriggerHandler {

    public DrawdownRequestHandler() {
        super('Drawdown_Request__c');
    }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        for (SObject rec : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED', 'Drawdown_Request__c',
                String.valueOf(rec.Id), 'Drawdown Request created.');
        }
        AuditEventLogger.flush();
    }

    override protected void afterUpdate(
        List<SObject> newList, Map<Id,SObject> newMap,
        List<SObject> oldList, Map<Id,SObject> oldMap
    ) {
        List<Id> toDisburse = new List<Id>();

        for (SObject newRec : newList) {
            SObject oldRec = oldMap.get(newRec.Id);
            String newStatus = (String) newRec.get('Status__c');
            String oldStatus = (String) oldRec.get('Status__c');

            if (newStatus != null && newStatus != oldStatus) {
                AuditEventLogger.logManual('STATUS_CHANGED', 'Drawdown_Request__c',
                    String.valueOf(newRec.Id),
                    'Drawdown Request status: ' + oldStatus + ' -> ' + newStatus);

                // When ops approves, create Disbursement Event and flip to Funded
                if (newStatus == 'Approved' && oldStatus != 'Approved') {
                    toDisburse.add(newRec.Id);
                }
            }
        }

        AuditEventLogger.flush();

        for (Id reqId : toDisburse) {
            Drawdown_Request__c req = [
                SELECT Id, Name, Debt_Position__c, Requested_Amount__c, Approved_Amount__c
                FROM Drawdown_Request__c WHERE Id = :reqId
            ];
            DisbursementService.createForDrawdown(req);
        }
    }
}