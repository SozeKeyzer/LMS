/**
 * ExceptionsInboxControllerTest
 * Covers ExceptionsInboxController.getExceptions() — all 4 exception categories:
 *   1. Failed Calculation_Run__c in last 7 days
 *   2. Pending Calculation_Override__c
 *   3. Debt_Position__c in Manual Calc_Mode
 *   4. Pending Bulk_Recalculation_Run__c
 */
@IsTest
private class ExceptionsInboxControllerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Exc FI', Status__c = 'Active');
        insert fi;

        // DP in Manual calc mode — covers the 3rd if-block
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Exc Manual DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Calc_Mode__c             = 'Manual',
            iPlatform_External_Id__c = 'EXCINB001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        // Failed Calculation_Run__c with Run_At in the 7-day window — covers 1st if-block
        Calculation_Run__c cr = new Calculation_Run__c(
            Status__c = 'Failed',
            Run_At__c = Datetime.now()
        );
        insert cr;

        // Pending Calculation_Override__c — covers 2nd if-block
        Calculation_Override__c co = new Calculation_Override__c(
            Status__c        = 'Pending'
        );
        insert co;

        // Pending Bulk_Recalculation_Run__c — covers 4th if-block
        Bulk_Recalculation_Run__c brr = new Bulk_Recalculation_Run__c(
            Approval_Status__c  = 'Pending',
            Execution_Status__c = 'Pending'
        );
        insert brr;
    }

    // All 4 if-blocks entered
    @IsTest
    static void testGetExceptions_AllFourCategories_ReturnsFourDTOs() {
        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        Assert.isNotNull(result, 'getExceptions must return non-null');
        Assert.areEqual(4, result.size(), 'All 4 exception categories must each produce one DTO');
    }

    // Verify DTO fields for Failed Calculation_Run__c (1st if-block)
    @IsTest
    static void testGetExceptions_FailedCalcRun_DTOFieldsPopulated() {
        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        ExceptionsInboxController.ExceptionItemDTO dto = null;
        for (ExceptionsInboxController.ExceptionItemDTO d : result) {
            if (d.objectType == 'Calculation_Run__c') { dto = d; break; }
        }
        Assert.isNotNull(dto, 'Must find a Calculation_Run__c DTO');
        Assert.areEqual('error',              dto.severity,    'Failed calc run must have severity=error');
        Assert.areEqual('Calculation_Run__c', dto.objectType);
        Assert.isNotNull(dto.id,    'DTO id must be populated');
        Assert.isNotNull(dto.count, 'DTO count must be populated');
        Assert.isNotNull(dto.label, 'DTO label must be populated');
    }

    // Verify DTO fields for Pending Calculation_Override__c (2nd if-block)
    @IsTest
    static void testGetExceptions_PendingOverride_DTOFieldsPopulated() {
        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        ExceptionsInboxController.ExceptionItemDTO dto = null;
        for (ExceptionsInboxController.ExceptionItemDTO d : result) {
            if (d.objectType == 'Calculation_Override__c') { dto = d; break; }
        }
        Assert.isNotNull(dto, 'Must find a Calculation_Override__c DTO');
        Assert.areEqual('warning', dto.severity, 'Override pending must have severity=warning');
        Assert.areEqual('Approve', dto.actionLabel);
    }

    // Verify DTO fields for Manual Mode DP (3rd if-block)
    @IsTest
    static void testGetExceptions_ManualModeDP_DTOFieldsPopulated() {
        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        ExceptionsInboxController.ExceptionItemDTO dto = null;
        for (ExceptionsInboxController.ExceptionItemDTO d : result) {
            if (d.objectType == 'Debt_Position__c') { dto = d; break; }
        }
        Assert.isNotNull(dto, 'Must find a Debt_Position__c (Manual mode) DTO');
        Assert.areEqual('error',  dto.severity);
        Assert.areEqual('Review', dto.actionLabel);
        Assert.isTrue(dto.detail.contains('Exc Manual DP'), 'Detail must mention the DP name');
    }

    // Verify DTO fields for Pending Bulk_Recalculation_Run__c (4th if-block)
    @IsTest
    static void testGetExceptions_PendingBulkRun_DTOFieldsPopulated() {
        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        ExceptionsInboxController.ExceptionItemDTO dto = null;
        for (ExceptionsInboxController.ExceptionItemDTO d : result) {
            if (d.objectType == 'Bulk_Recalculation_Run__c') { dto = d; break; }
        }
        Assert.isNotNull(dto, 'Must find a Bulk_Recalculation_Run__c DTO');
        Assert.areEqual('info',    dto.severity);
        Assert.areEqual('Approve', dto.actionLabel);
    }

    // Empty org state — all 4 if-blocks skipped → empty list
    @IsTest
    static void testGetExceptions_NoExceptionData_ReturnsEmptyList() {
        delete [SELECT Id FROM Calculation_Run__c];
        delete [SELECT Id FROM Calculation_Override__c];
        delete [SELECT Id FROM Bulk_Recalculation_Run__c];
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Calc_Mode__c = 'Engine');
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        List<ExceptionsInboxController.ExceptionItemDTO> result = ExceptionsInboxController.getExceptions();
        Test.stopTest();

        Assert.isNotNull(result, 'Empty result must still be non-null');
        Assert.isTrue(result.isEmpty(), 'No exception data must return empty list');
    }
}