/**
 * InterestReserveTransactionHandler
 * On afterInsert: updates Current_Reserve_Balance__c on parent Interest_Reserve__c.
 * Fund/Replenish = positive delta. Draw/Release = negative delta.
 * Maintains immutability — guard prevents edits after creation.
 */
public class InterestReserveTransactionHandler extends LMSTriggerHandler {

    public InterestReserveTransactionHandler() { super('Interest_Reserve_Transaction__c'); }

    override protected void afterInsert(List<SObject> newList, Map<Id,SObject> newMap) {
        // Aggregate deltas per parent Interest_Reserve
        Map<Id,Decimal> deltaMap = new Map<Id,Decimal>();
        for (SObject sobj : newList) {
            Interest_Reserve_Transaction__c txn = (Interest_Reserve_Transaction__c) sobj;
            Decimal delta = txn.Amount__c != null ? txn.Amount__c : 0;
            // Draw and Release reduce the balance
            if (txn.Type__c == 'Draw' || txn.Type__c == 'Release') delta = -delta;
            Decimal current = deltaMap.get(txn.Interest_Reserve__c);
            deltaMap.put(txn.Interest_Reserve__c, (current != null ? current : 0) + delta);
        }

        // Fetch current balances
        Map<Id,Interest_Reserve__c> reserves = new Map<Id,Interest_Reserve__c>([
            SELECT Id, Current_Reserve_Balance__c
            FROM Interest_Reserve__c WHERE Id IN :deltaMap.keySet()
        ]);

        List<Interest_Reserve__c> toUpdate = new List<Interest_Reserve__c>();
        for (Id resId : deltaMap.keySet()) {
            Interest_Reserve__c res = reserves.get(resId);
            if (res == null) continue;
            Decimal newBalance = (res.Current_Reserve_Balance__c != null ? res.Current_Reserve_Balance__c : 0)
                               + deltaMap.get(resId);
            toUpdate.add(new Interest_Reserve__c(Id = resId, Current_Reserve_Balance__c = newBalance));
        }

        TriggerContext.getInstance().bypassGuards = true;
        if (!toUpdate.isEmpty()) update toUpdate;
        TriggerContext.getInstance().bypassGuards = false;

        for (SObject sobj : newList) {
            AuditEventLogger.logEngine('RECORD_CREATED','Interest_Reserve_Transaction__c',
                String.valueOf(sobj.Id),'Reserve transaction: ' + sobj.get('Type__c') + ' | ' + sobj.get('Amount__c'));
        }
        AuditEventLogger.flush();
    }
}