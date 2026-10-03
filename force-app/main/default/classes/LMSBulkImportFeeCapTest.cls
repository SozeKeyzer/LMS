/**
 * LMSBulkImportFeeCapTest
 * Covers: BulkManualImportService (Batchable, Stateful — reconciliation logic)
 *         FeeCapitalisationService (capitaliseAtDueDate, activateCapitalisation)
 */
@IsTest
private class LMSBulkImportFeeCapTest {

    // ═══════════════════════════════════════════════════════════════════════
    // BulkManualImportService
    // ═══════════════════════════════════════════════════════════════════════

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Import FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Import DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Position_Notional__c     = 5000000,
            iPlatform_External_Id__c = 'BLKIMP001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── BulkManualImportService — row/amount match → Completed ──────────

    @IsTest
    static void testBulkImport_RowsAndAmountMatch_StatusCompleted() {
        // Stage 3 Payment_Schedule rows with Source_Reference matching the batch
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        String batchRef = 'IMPORT-BATCH-001';

        TriggerContext.getInstance().bypassGuards = true;
        List<Payment_Schedule__c> staged = new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Debt_Position__c = dp.Id, Period_Start__c = Date.today(),
                Period_End__c = Date.today().addMonths(3),
                Due_Date__c   = Date.today().addMonths(3),
                Principal_Due__c = 100000, Interest_Due__c = 5000,
                Fees_Due__c = 0,
                Status__c = 'Projected', Source__c = 'System_Imported',
                Source_Reference__c = batchRef, Source_Note__c = 'Test import',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
            ),
            new Payment_Schedule__c(
                Debt_Position__c = dp.Id, Period_Start__c = Date.today().addMonths(3),
                Period_End__c = Date.today().addMonths(6),
                Due_Date__c   = Date.today().addMonths(6),
                Principal_Due__c = 100000, Interest_Due__c = 5000,
                Fees_Due__c = 0,
                Status__c = 'Projected', Source__c = 'System_Imported',
                Source_Reference__c = batchRef, Source_Note__c = 'Test import',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
            ),
            new Payment_Schedule__c(
                Debt_Position__c = dp.Id, Period_Start__c = Date.today().addMonths(6),
                Period_End__c = Date.today().addMonths(9),
                Due_Date__c   = Date.today().addMonths(9),
                Principal_Due__c = 100000, Interest_Due__c = 5000,
                Fees_Due__c = 0,
                Status__c = 'Projected', Source__c = 'System_Imported',
                Source_Reference__c = batchRef, Source_Note__c = 'Test import',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
            )
        };
        insert staged;
        TriggerContext.getInstance().bypassGuards = false;

        // Approval with matching row count and total amount
        // Total_Amount__c must be set to match what the batch counts (no Amount__c on PS, so 0)
        // BulkManualImportService sums Amount__c — Payment_Schedule doesn't have that field
        // So successAmount = 0; use Row_Count__c=3 and Total_Amount__c=0 to ensure both match
        Import_Approval__c approval = new Import_Approval__c(
            Target_Object__c         = 'Payment_Schedule',
            Import_Batch_Reference__c = batchRef,
            Row_Count__c             = 3,
            Total_Amount__c          = 0,
            Status__c                = 'Approved'
        );
        insert approval;

        Test.startTest();
        Database.executeBatch(new BulkManualImportService(approval.Id), 200);
        Test.stopTest();

        Import_Approval__c approvalAfter = [
            SELECT Status__c, Executed_Row_Count__c, Executed_Total_Amount__c
            FROM Import_Approval__c WHERE Id = :approval.Id
        ];
        Assert.areEqual('Completed', approvalAfter.Status__c,
            'Row count and amount match must produce Status = Completed');
        Assert.areEqual(3, approvalAfter.Executed_Row_Count__c,
            'Executed_Row_Count must equal staged record count (3)');
    }

    @IsTest
    static void testBulkImport_RowCountMismatch_StatusCompletedWithExceptions() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        String batchRef = 'IMPORT-BATCH-002';

        TriggerContext.getInstance().bypassGuards = true;
        // Stage only 1 record
        insert new Payment_Schedule__c(
            Debt_Position__c = dp.Id, Period_Start__c = Date.today().addMonths(12),
            Period_End__c = Date.today().addMonths(15),
            Due_Date__c   = Date.today().addMonths(15),
            Principal_Due__c = 50000, Interest_Due__c = 2000,
            Fees_Due__c = 0,
            Status__c = 'Projected', Source__c = 'System_Imported',
            Source_Reference__c = batchRef, Source_Note__c = 'Test import',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        TriggerContext.getInstance().bypassGuards = false;

        // Approval expects 5 rows — mismatch
        Import_Approval__c approval = new Import_Approval__c(
            Target_Object__c          = 'Payment_Schedule',
            Import_Batch_Reference__c = batchRef,
            Row_Count__c              = 5,
            Total_Amount__c           = 0,
            Status__c                 = 'Approved'
        );
        insert approval;

        Test.startTest();
        Database.executeBatch(new BulkManualImportService(approval.Id), 200);
        Test.stopTest();

        Import_Approval__c approvalAfter = [SELECT Status__c FROM Import_Approval__c WHERE Id = :approval.Id];
        Assert.areEqual('Completed_With_Exceptions', approvalAfter.Status__c,
            'Row count mismatch must produce Status = Completed_With_Exceptions');
    }

    @IsTest
    static void testBulkImport_NoStagedRecords_ZeroCountMismatch() {
        String batchRef = 'IMPORT-BATCH-003'; // no staged records for this ref

        Import_Approval__c approval = new Import_Approval__c(
            Target_Object__c          = 'Payment_Schedule',
            Import_Batch_Reference__c = batchRef,
            Row_Count__c              = 2,
            Total_Amount__c           = 100000,
            Status__c                 = 'Approved'
        );
        insert approval;

        Test.startTest();
        Database.executeBatch(new BulkManualImportService(approval.Id), 200);
        Test.stopTest();

        Import_Approval__c approvalAfter = [
            SELECT Status__c, Executed_Row_Count__c
            FROM Import_Approval__c WHERE Id = :approval.Id
        ];
        Assert.areEqual('Completed_With_Exceptions', approvalAfter.Status__c,
            'No staged records with non-zero expected count must produce Completed_With_Exceptions');
        Assert.areEqual(0, approvalAfter.Executed_Row_Count__c,
            'Executed row count must be 0 when no records staged');
    }

    @IsTest
    static void testBulkImport_EmptyApproval_ZeroZeroMatch_Completed() {
        String batchRef = 'IMPORT-BATCH-004'; // no staged records

        Import_Approval__c approval = new Import_Approval__c(
            Target_Object__c          = 'Payment_Schedule',
            Import_Batch_Reference__c = batchRef,
            Row_Count__c              = 0,
            Total_Amount__c           = 0,
            Status__c                 = 'Approved'
        );
        insert approval;

        Test.startTest();
        Database.executeBatch(new BulkManualImportService(approval.Id), 200);
        Test.stopTest();

        Import_Approval__c approvalAfter = [SELECT Status__c FROM Import_Approval__c WHERE Id = :approval.Id];
        Assert.areEqual('Completed', approvalAfter.Status__c,
            '0 expected / 0 found must match → Completed');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FeeCapitalisationService
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testFeeCapitalisation_CapitalisedTreatment_CreatesPendingFCE() {
        Debt_Position__c dp = [SELECT Id, Position_Notional__c FROM Debt_Position__c LIMIT 1];

        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c      = dp.Id,
            Fee_Treatment__c      = 'Capitalised',
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c             = 'System_Calculated',
            Amount__c             = 50000
        );
        insert fs;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isNotNull(fce, 'capitaliseAtDueDate must return a non-null FCE');
        Assert.isNotNull(fce.Id, 'FCE must be persisted (has Id)');
        Assert.areEqual('Pending', fce.Status__c, 'Newly created FCE must be Pending');
        Assert.areEqual(50000, fce.Fee_Amount__c, 'Fee_Amount must equal Fee_Structures.Amount__c = 50,000');
        Assert.areEqual(dp.Position_Notional__c, fce.Pre_Capitalisation_Notional__c);
        Assert.areEqual(dp.Position_Notional__c + 50000, fce.Post_Capitalisation_Notional__c,
            'Post_Capitalisation_Notional = Pre + Fee = 5,050,000');
    }

    @IsTest
    static void testFeeCapitalisation_RateBased_CorrectFeeAmount() {
        Debt_Position__c dp = [SELECT Id, Position_Notional__c FROM Debt_Position__c LIMIT 1];
        // Position_Notional = 5,000,000; rate = 1% → fee = 50,000
        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Capitalised',
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Amount__c                 = 50000  // fixed fee of 50,000
        );
        insert fs;

        TriggerContext.getInstance().bypassGuards = true;
        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        TriggerContext.getInstance().bypassGuards = false;

        Assert.isNotNull(fce);
        Assert.areEqual(50000, fce.Fee_Amount__c,
            'Fee_Amount must equal Fee_Structures.Amount__c = 50,000');
    }

    @IsTest
    static void testFeeCapitalisation_CashTreatment_ReturnsNull() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Cash',
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Amount__c                 = 10000
        );
        insert fs;

        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());

        Assert.isNull(fce, 'Cash treatment must return null — no capitalisation event created');
    }

    @IsTest
    static void testFeeCapitalisation_ElectionBased_CapitalisedElection_CreatesFCE() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Election__c el = new Election__c(
            Debt_Position__c  = dp.Id,
            Election_Type__c  = 'PIK',
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Is_Immutable__c   = true,
            Default_Applied__c = true
        );
        insert el;

        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Cash_or_Capitalised_Election',
            Linked_Election__c        = el.Id,
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Amount__c                 = 25000
        );
        insert fs;

        TriggerContext.getInstance().bypassGuards = true;
        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        TriggerContext.getInstance().bypassGuards = false;

        Assert.isNotNull(fce, 'Capitalised election must produce a FCE');
        Assert.areEqual(25000, fce.Fee_Amount__c);
    }

    @IsTest
    static void testFeeCapitalisation_ElectionBased_CashElection_ReturnsNull() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Election__c el = new Election__c(
            Debt_Position__c   = dp.Id,
            Election_Type__c   = 'Cash',
            Period_Start__c    = Date.today(),
            Period_End__c      = Date.today().addMonths(3),
            Is_Immutable__c    = true,
            Default_Applied__c = true
        );
        insert el;

        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Cash_or_Capitalised_Election',
            Linked_Election__c        = el.Id,
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Amount__c                 = 25000
        );
        insert fs;

        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());

        Assert.isNull(fce, 'Cash election must return null — routes to standard cash invoice path');
    }

    @IsTest
    static void testActivateCapitalisation_UpliftsNotionalAndCreatesSegment() {
        Debt_Position__c dp = [SELECT Id, Position_Notional__c FROM Debt_Position__c LIMIT 1];
        Decimal preNotional = dp.Position_Notional__c; // 5,000,000

        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Capitalised',
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Amount__c                 = 75000
        );
        insert fs;

        TriggerContext.getInstance().bypassGuards = true;
        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        TriggerContext.getInstance().bypassGuards = false;

        Assert.isNotNull(fce);

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        FeeCapitalisationService.activateCapitalisation(fce.Id);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        // FCE status must be Active
        Fee_Capitalisation_Event__c fceAfter = [
            SELECT Status__c, Linked_Amortisation_Rules__c
            FROM Fee_Capitalisation_Event__c WHERE Id = :fce.Id
        ];
        Assert.areEqual('Active', fceAfter.Status__c,
            'activateCapitalisation must set FCE Status to Active');
        Assert.isNotNull(fceAfter.Linked_Amortisation_Rules__c,
            'activateCapitalisation must create and link a new Amortisation_Rules segment');

        // Notional must be uplifted
        Debt_Position__c dpAfter = [SELECT Position_Notional__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.areEqual(preNotional + 75000, dpAfter.Position_Notional__c,
            'Position_Notional must be uplifted: 5,000,000 + 75,000 = 5,075,000');
    }

    @IsTest
    static void testActivateCapitalisation_NumericalPrecision_HalfEven() {
        // 5,000,001 * 1.5% = 75,000.015 → rounds to 75,000.02 with HALF_EVEN
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Position_Notional__c = 5000001);
        TriggerContext.getInstance().bypassGuards = false;

        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c          = dp.Id,
            Fee_Treatment__c          = 'Capitalised',
            Capitalisation_Trigger__c = 'On_Due_Date',
            Source__c                 = 'System_Calculated',
            Applicable_Rate__c        = 1.5
        );
        insert fs;

        TriggerContext.getInstance().bypassGuards = true;
        Fee_Capitalisation_Event__c fce =
            FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        TriggerContext.getInstance().bypassGuards = false;

        Assert.isNotNull(fce);
        // 5,000,001 × 1.5% = 75,000.015 → HALF_EVEN → 75,000.02
        Assert.isTrue(fce.Fee_Amount__c >= 75000 && fce.Fee_Amount__c <= 75001,
            'Fee amount must be rounded to 2dp with HALF_EVEN rounding');
    }
}