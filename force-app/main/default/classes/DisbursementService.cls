/**
 * DisbursementService
 * Creates Disbursement_Event records (outbound cash per cash model).
 * Called when a Drawdown_Request is funded.
 * Sets Source = System_Calculated, Is_Immutable = false (set true on confirmation).
 */
public class DisbursementService {

    public static Disbursement_Event__c createForDrawdown(Drawdown_Request__c request) {
        String corrId = TriggerContext.getInstance().correlationId;
        Decimal fundedAmount = request.Approved_Amount__c != null
            ? request.Approved_Amount__c : request.Requested_Amount__c;

        Disbursement_Event__c de = new Disbursement_Event__c(
            Debt_Position__c   = request.Debt_Position__c,
            Amount__c          = fundedAmount,
            Correlation_Id__c  = corrId,
            Source__c          = 'System_Calculated',
            Source_Reference__c= String.valueOf(request.Id),
            Source_Note__c     = 'Auto-created from approved Drawdown Request: ' + request.Name,
            Is_Immutable__c    = false,
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c     = String.valueOf(request.Id) + '-' + Date.today().format()
        );

        TriggerContext.getInstance().bypassGuards = true;
        insert de;

        // Link back to drawdown request
        update new Drawdown_Request__c(
            Id                        = request.Id,
            Status__c                 = 'Funded',
            Actual_Drawdown_Date__c   = Date.today(),
            Funded_Amount__c          = fundedAmount,
            Linked_Disbursement_Event__c = de.Id
        );
        TriggerContext.getInstance().bypassGuards = false;

        AuditEventLogger.logEngine('DISBURSEMENT_RECORDED','Disbursement_Event__c',
            String.valueOf(de.Id),'Disbursement created for drawdown request ' + request.Name + '. Amount: ' + fundedAmount);
        AuditEventLogger.flush();
        return de;
    }

    @InvocableMethod(label='Create Disbursement for Drawdown' category='LMS')
    public static List<Id> createFromFlow(List<Id> drawdownRequestIds) {
        List<Id> disbIds = new List<Id>();
        for (Id reqId : drawdownRequestIds) {
            Drawdown_Request__c req = [
                SELECT Id, Name, Debt_Position__c, Requested_Amount__c, Approved_Amount__c
                FROM Drawdown_Request__c WHERE Id = :reqId
            ];
            disbIds.add(createForDrawdown(req).Id);
        }
        return disbIds;
    }
}