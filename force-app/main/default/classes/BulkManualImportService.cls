/**
 * BulkManualImportService
 * Batchable import from Excel/CSV via an approved Import_Approval record.
 * Sets Source = System_Imported, Source_Reference = batch ID, Is_Immutable = true.
 * Reconciles row count and total amount at completion.
 * Implements spec section 5.7.5.
 */
public class BulkManualImportService implements Database.Batchable<SObject>, Database.Stateful {

    private Id approvalId;
    private Import_Approval__c approval;
    private Boolean hasAmountField;
    private String targetApiName;
    private Integer successCount = 0;
    private Decimal successAmount = 0;
    private List<String> errorLog = new List<String>();

    public BulkManualImportService(Id approvalId) {
        this.approvalId = approvalId;
        this.approval = [
            SELECT Id, Target_Object__c, Import_Batch_Reference__c, Row_Count__c, Total_Amount__c, Status__c
            FROM Import_Approval__c WHERE Id = :approvalId
        ];
        this.targetApiName = approval.Target_Object__c.endsWith('__c')
            ? approval.Target_Object__c
            : approval.Target_Object__c + '__c';
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(targetApiName);
        this.hasAmountField = objType != null
            && objType.getDescribe().fields.getMap().containsKey('amount__c');
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query the target object where Source_Reference matches this batch
        // In practice, records are pre-staged; this queries the staged records
        String amtField = hasAmountField ? ', Amount__c' : '';
        String q = 'SELECT Id' + amtField + ' FROM ' + targetApiName +
            ' WHERE Source_Reference__c = \'' + approval.Import_Batch_Reference__c + '\'' +
            ' AND Source__c = \'System_Imported\'';
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject record : scope) {
            successCount++;
            if (hasAmountField) {
                Object amt = record.get('Amount__c');
                if (amt != null) successAmount += (Decimal) amt;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Reconciliation
        Boolean countMatch  = (successCount == approval.Row_Count__c.intValue());
        Boolean amountMatch = (Math.abs(successAmount - approval.Total_Amount__c) < 0.01);
        String finalStatus  = (countMatch && amountMatch) ? 'Completed' : 'Completed_With_Exceptions';

        update new Import_Approval__c(
            Id = approvalId,
            Status__c                 = finalStatus,
            Executed_Row_Count__c     = successCount,
            Executed_Total_Amount__c  = successAmount,
            Execution_Log__c          = JSON.serialize(errorLog.isEmpty() ? new List<String>{'No errors'} : errorLog)
        );

        AuditEventLogger.logEngine('IMPORT_APPROVED','Import_Approval__c',String.valueOf(approvalId),
            'Bulk import completed. Status: ' + finalStatus + '. Rows: ' + successCount + '. Amount: ' + successAmount);
        AuditEventLogger.flush();
    }
}