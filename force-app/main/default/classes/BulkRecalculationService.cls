public class BulkRecalculationService implements Queueable {

    private Id bulkRunId;

    public BulkRecalculationService(Id bulkRunId) {
        this.bulkRunId = bulkRunId;
    }

    public void execute(QueueableContext context) {
        Bulk_Recalculation_Run__c bulkRun = [
            SELECT Id, Calc_Definition__c, Target_Version__c,
                   Record_Selector_Query__c, Approval_Status__c
            FROM Bulk_Recalculation_Run__c
            WHERE Id = :bulkRunId
        ];

        if (bulkRun.Approval_Status__c != 'Approved') {
            return;
        }

        bulkRun.Execution_Status__c = 'Running';
        bulkRun.Started_At__c = Datetime.now();
        update bulkRun;

        Integer processed = 0;
        Integer failed = 0;

        try {
            if (String.isNotBlank(bulkRun.Record_Selector_Query__c)) {
                List<SObject> records = Database.query(bulkRun.Record_Selector_Query__c);
                for (SObject rec : records) {
                    try {
                        CalculationOrchestrator.run(bulkRun.Calc_Definition__c, rec.Id, 'Commit');
                        processed++;
                    } catch (Exception e) {
                        failed++;
                    }
                }
            }
            bulkRun.Execution_Status__c = 'Completed';
        } catch (Exception e) {
            bulkRun.Execution_Status__c = 'Failed';
        }

        bulkRun.Records_Processed__c = processed;
        bulkRun.Records_Failed__c = failed;
        bulkRun.Completed_At__c = Datetime.now();
        update bulkRun;
    }
}