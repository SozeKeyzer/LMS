/**
 * PeriodCloseBatch — runs on Period_End date.
 * Crystallises Accrual_Daily rows (Is_Immutable=true), rolls up Interest_Due on
 * Payment_Schedule per Rule R1.
 *
 * Handles two close paths:
 *   ACTIVE  — period still open when batch runs (standard); batch closes it.
 *   CLOSED  — DailyAccrualBatch already closed the IP on Period_End-1; batch
 *             still rolls up Interest_Due (which DailyAccrualBatch does not do).
 */
public class PeriodCloseBatch implements Database.Batchable<SObject> {

    private Date closeDate;

    public PeriodCloseBatch()        { this.closeDate = Date.today(); }
    public PeriodCloseBatch(Date d)  { this.closeDate = d; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Debt_Position__c, Period_End__c, Period_Start__c, Status__c
            FROM Interest_Period__c
            WHERE (Status__c = 'Active' AND Period_End__c <= :closeDate)
               OR (Status__c = 'Closed' AND Period_End__c = :closeDate)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject s : scope) {
            Interest_Period__c ip = (Interest_Period__c) s;

            // Roll up Effective_Value (Override if set, else Accrued_Amount) per Rule R1
            AggregateResult[] totals = [
                SELECT SUM(Effective_Value__c) total
                FROM Accrual_Daily__c
                WHERE Interest_Period__c = :ip.Id AND Is_PIK__c = false
            ];
            Decimal interestDue = totals.isEmpty() ? 0 : (Decimal)(totals[0].get('total') ?? 0);

            // Update matching Payment_Schedule row
            List<Payment_Schedule__c> schedules = [
                SELECT Id FROM Payment_Schedule__c
                WHERE Debt_Position__c = :ip.Debt_Position__c
                AND Period_Start__c = :ip.Period_Start__c
            ];
            TriggerContext.getInstance().bypassGuards = true;
            for (Payment_Schedule__c ps : schedules) {
                update new Payment_Schedule__c(Id = ps.Id, Interest_Due__c = interestDue, Status__c = 'Due');
            }

            // Close only if still Active — DailyAccrualBatch may have already closed it
            if (ip.Status__c == 'Active') {
                InterestPeriodService.closePeriod(ip.Id);
            } else {
                AuditEventLogger.logEngine('PERIOD_CLOSED', 'Interest_Period__c',
                    String.valueOf(ip.Id),
                    'Interest_Due rolled up for already-closed period. Amount: ' + interestDue);
            }
            TriggerContext.getInstance().bypassGuards = false;

            // PIK capitalisation — capitalise() returns early if no PIK accruals exist
            PIKCapitalisationService.capitalise(ip.Debt_Position__c, ip.Id);
        }
        AuditEventLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        AuditEventLogger.logEngine('PERIOD_CLOSED', 'PeriodCloseBatch', null,
            'PeriodCloseBatch complete for close date: ' + closeDate);
        AuditEventLogger.flush();
    }
}