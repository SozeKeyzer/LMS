/**
 * AdjustmentService
 * Handles Payment_Adjustment lifecycle.
 * On Status = Effective: updates Net_Due on parent Payment_Schedule.
 * 4-eyes check: Requested_By != Approved_By enforced here (belt + VR.PAD.05 suspenders).
 */
public class AdjustmentService {

    public static void handleEffective(List<Payment_Adjustment__c> adjustments, Map<Id,Payment_Adjustment__c> oldMap) {
        List<Payment_Adjustment__c> justEffective = new List<Payment_Adjustment__c>();
        for (Payment_Adjustment__c adj : adjustments) {
            if (adj.Status__c == 'Effective' && oldMap.get(adj.Id).Status__c != 'Effective') {
                // 4-eyes enforcement
                if (adj.Requested_By__c == adj.Approved_By__c) {
                    adj.addError('Approver must differ from the person who requested this adjustment (4-eyes rule).');
                    continue;
                }
                justEffective.add(adj);
            }
        }
        if (justEffective.isEmpty()) return;

        Set<Id> scheduleIds = new Set<Id>();
        for (Payment_Adjustment__c adj : justEffective) scheduleIds.add(adj.Original_Schedule__c);

        Map<Id,Payment_Schedule__c> schedules = new Map<Id,Payment_Schedule__c>([
            SELECT Id, Net_Due__c, Total_Due__c
            FROM Payment_Schedule__c WHERE Id IN :scheduleIds
        ]);

        // Aggregate deltas per schedule
        Map<Id,Decimal> deltaMap = new Map<Id,Decimal>();
        for (Payment_Adjustment__c adj : justEffective) {
            Decimal current = deltaMap.get(adj.Original_Schedule__c) ?? 0;
            deltaMap.put(adj.Original_Schedule__c, current + adj.Delta__c);
        }

        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (Id schedId : deltaMap.keySet()) {
            Payment_Schedule__c ps = schedules.get(schedId);
            if (ps != null) {
                Decimal base = ps.Net_Due__c ?? ps.Total_Due__c ?? 0;
                toUpdate.add(new Payment_Schedule__c(Id = schedId, Net_Due__c = base + deltaMap.get(schedId)));
            }
        }

        TriggerContext.getInstance().bypassGuards = true;
        if (!toUpdate.isEmpty()) update toUpdate;
        TriggerContext.getInstance().bypassGuards = false;

        for (Payment_Adjustment__c adj : justEffective) {
            AuditEventLogger.logManual('PAYMENT_ADJUSTED', 'Payment_Adjustment__c',
                String.valueOf(adj.Id), 'Adjustment effective. Delta: ' + adj.Delta__c);
        }
        AuditEventLogger.flush();
    }
}