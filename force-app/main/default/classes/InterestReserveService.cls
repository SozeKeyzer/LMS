/**
 * InterestReserveService
 * NOTE: Interest_Reserve__c parent lookup field name to Financial_Instrument__c
 * is not known at code-generation time. Uses dynamic SOQL with IR_FI_LOOKUP_FIELD.
 * Update IR_FI_LOOKUP_FIELD to the actual field name in your org.
 * Check: Setup → Object Manager → Interest_Reserve__c → Fields.
 */
public class InterestReserveService {

    @TestVisible
    static String IR_FI_LOOKUP_FIELD = 'Financial_Instrument__c';

    public static void autoApplyReserve(Payment_Schedule__c schedule, Debt_Position__c dp) {
        if (dp.Financial_Instrument__c == null) return;

        List<Interest_Reserve__c> reserves = new List<Interest_Reserve__c>();
        try {
            Id fiId = dp.Financial_Instrument__c;
            String soql = 'SELECT Id, Current_Reserve_Balance__c FROM Interest_Reserve__c'
                + ' WHERE ' + IR_FI_LOOKUP_FIELD + ' = :fiId'
                + ' AND Current_Reserve_Balance__c > 0 LIMIT 1';
            reserves = (List<Interest_Reserve__c>) Database.query(soql);
        } catch (Exception e) {
            AuditEventLogger.logEngine('GUARD_VIOLATION_BLOCKED','Interest_Reserve__c',null,
                'Reserve query failed — check IR_FI_LOOKUP_FIELD. Error: ' + e.getMessage());
            AuditEventLogger.flush();
            return;
        }

        if (reserves.isEmpty()) return;

        Interest_Reserve__c reserve = reserves[0];
        Decimal drawAmount = schedule.Net_Due__c != null ? schedule.Net_Due__c : schedule.Total_Due__c;
        if (drawAmount == null || drawAmount <= 0) return;
        if (reserve.Current_Reserve_Balance__c < drawAmount) return;

        String corrId = TriggerContext.getInstance().correlationId;
        Interest_Reserve_Transaction__c draw = new Interest_Reserve_Transaction__c(
            Type__c                    = 'Draw',
            Interest_Reserve__c        = reserve.Id,
            Transaction_Date__c        = Date.today(),
            Value_Date__c              = Date.today(),
            Amount__c                  = drawAmount,
            Linked_Payment_Schedule__c = schedule.Id,
            Correlation_Id__c          = corrId,
            Source__c                  = 'System_Calculated',
            External_Id__c             = String.valueOf(reserve.Id) + '-Draw-'
                                         + Date.today().format() + '-' + drawAmount
        );

        TriggerContext.getInstance().bypassGuards = true;
        insert draw;
        TriggerContext.getInstance().bypassGuards = false;

        AuditEventLogger.logEngine('PAYMENT_ALLOCATED','Interest_Reserve__c',
            String.valueOf(reserve.Id),
            'Reserve auto-draw: ' + drawAmount + ' for schedule ' + schedule.Id);
        AuditEventLogger.flush();
    }

    @InvocableMethod(label='Fund Interest Reserve' category='LMS')
    public static void fundReserve(List<FundReserveRequest> requests) {
        List<Interest_Reserve_Transaction__c> toInsert = new List<Interest_Reserve_Transaction__c>();
        for (FundReserveRequest req : requests) {
            toInsert.add(new Interest_Reserve_Transaction__c(
                Interest_Reserve__c           = req.reserveId,
                Type__c                       = req.transactionType,
                Transaction_Date__c           = req.transactionDate,
                Value_Date__c                 = req.valueDate != null ? req.valueDate : req.transactionDate,
                Amount__c                     = req.amount,
                Linked_Payment_Transaction__c = req.paymentTransactionId,
                Correlation_Id__c             = TriggerContext.getInstance().correlationId,
                Source__c                     = 'Manual_Entry',
                External_Id__c                = req.reserveId + '-' + req.transactionType
                                                + '-' + req.transactionDate + '-' + req.amount
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
        AuditEventLogger.flush();
    }

    public class FundReserveRequest {
        @InvocableVariable(required=true  label='Reserve ID')          public Id     reserveId;
        @InvocableVariable(required=true  label='Transaction Type')    public String transactionType;
        @InvocableVariable(required=true  label='Transaction Date')    public Date   transactionDate;
        @InvocableVariable(required=false label='Value Date')          public Date   valueDate;
        @InvocableVariable(required=true  label='Amount')              public Decimal amount;
        @InvocableVariable(required=false label='Payment Transaction') public Id     paymentTransactionId;
    }
}