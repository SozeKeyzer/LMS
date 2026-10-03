/**
 * LMSDrawdownTest
 * Covers: DrawdownRequestValidationService (ValidationResult), DisbursementService.createForDrawdown,
 *         DrawdownRequestHandler.afterUpdate (Approved triggers DisbursementService)
 */
@IsTest
private class LMSDrawdownTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'DD FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'DD DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'DDOWN-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        // Availability_Period__c is the object checked by DrawdownRequestValidationService
        Availability_Period__c ap = new Availability_Period__c(
            Financial_Instrument__c = fi.Id
        );
        insert ap;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── DrawdownRequestValidationService ────────────────────────────────────

    @IsTest
    static void testValidation_NoAvailabilityPeriod_Fails() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        // Remove availability period
        delete [SELECT Id FROM Availability_Period__c WHERE Financial_Instrument__c = :fi.Id];

        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 1000000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                 = 'Draft'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dr;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        DrawdownRequestValidationService.ValidationResult result =
            DrawdownRequestValidationService.validate(dr);
        Test.stopTest();

        Assert.isFalse(result.isValid, 'No availability period must produce a validation error');
        Assert.isFalse(result.errors.isEmpty(), 'Must have at least one error message');
    }

    @IsTest
    static void testValidation_NoticePeriodViolation_Fails() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        // Notice_Period_Days__c is on DR, not DP
        // Request with notice received today but drawdown tomorrow (1 day) vs 3 day notice
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 500000,
            Requested_Drawdown_Date__c = Date.today().addDays(1),
            Notice_Period_Days__c     = 3,
            Notice_Received_Date__c   = Date.today(),
            Status__c                 = 'Draft'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dr;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        DrawdownRequestValidationService.ValidationResult result =
            DrawdownRequestValidationService.validate(dr);
        Test.stopTest();

        Assert.isFalse(result.isValid, 'Insufficient notice period must produce validation error');
    }

    @IsTest
    static void testValidation_ZeroAmount_Fails() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        // Do not insert — org VR blocks amount=0 inserts even with bypassGuards.
        // validate() reads fields from the passed-in object directly, no re-query by Id.
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c           = dp.Id,
            Requested_Amount__c        = 0,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                  = 'Draft'
        );

        Test.startTest();
        DrawdownRequestValidationService.ValidationResult result =
            DrawdownRequestValidationService.validate(dr);
        Test.stopTest();

        Assert.isFalse(result.isValid, 'Zero amount must produce validation error');
    }

    @IsTest
    static void testValidation_Valid_NoErrors() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        // Availability period exists (from setup), amount > 0, no notice check
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 1000000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                 = 'Draft'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dr;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        DrawdownRequestValidationService.ValidationResult result =
            DrawdownRequestValidationService.validate(dr);
        Test.stopTest();

        Assert.isTrue(result.isValid, 'Valid drawdown request must produce no errors');
        Assert.isTrue(result.errors.isEmpty(), 'Errors list must be empty for valid request');
    }

    // ─── DisbursementService.createForDrawdown ────────────────────────────────

    @IsTest
    static void testDisbursementService_CreateForDrawdown_LinksToDrawdownRequest() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 2000000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                 = 'Approved'
        );
        insert dr;

        Drawdown_Request__c drFull = [
            SELECT Id, Name, Debt_Position__c, Requested_Amount__c, Approved_Amount__c
            FROM Drawdown_Request__c WHERE Id = :dr.Id
        ];
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        Disbursement_Event__c de = DisbursementService.createForDrawdown(drFull);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isNotNull(de, 'createForDrawdown must return a Disbursement_Event');
        Assert.isNotNull(de.Id, 'Returned Disbursement_Event must be persisted');

        Drawdown_Request__c drAfter = [
            SELECT Status__c, Linked_Disbursement_Event__c
            FROM Drawdown_Request__c WHERE Id = :dr.Id
        ];
        Assert.areEqual('Funded', drAfter.Status__c, 'Drawdown_Request must be updated to Funded');
        Assert.areEqual(de.Id, drAfter.Linked_Disbursement_Event__c,
            'DR must be linked to the created Disbursement_Event');
    }

    // ─── DrawdownRequestHandler.afterUpdate ───────────────────────────────────

    @IsTest
    static void testDrawdownRequestHandler_ApprovedTriggersDisbursement() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 750000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                 = 'Draft'
        );
        insert dr;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        update new Drawdown_Request__c(Id = dr.Id, Status__c = 'Approved');
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Drawdown_Request__c drAfter = [
            SELECT Status__c, Linked_Disbursement_Event__c
            FROM Drawdown_Request__c WHERE Id = :dr.Id
        ];
        Assert.isNotNull(drAfter.Linked_Disbursement_Event__c,
            'Approved status transition must trigger DisbursementService and link event');
    }

    @IsTest
    static void testDrawdownRequestHandler_OtherStatusChange_NoDisbursement() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c          = dp.Id,
            Requested_Amount__c       = 500000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                 = 'Draft'
        );
        insert dr;
        update new Drawdown_Request__c(Id = dr.Id, Status__c = 'Cancelled');
        TriggerContext.getInstance().bypassGuards = false;

        Drawdown_Request__c drAfter = [
            SELECT Linked_Disbursement_Event__c FROM Drawdown_Request__c WHERE Id = :dr.Id
        ];
        Assert.isNull(drAfter.Linked_Disbursement_Event__c,
            'Non-Approved status change must not trigger DisbursementService');
    }

    // ─── DrawdownRequestValidationService — extra paths ──────────────────────

    @IsTest
    static void testValidate_NullDebtPosition_ReturnsError() {
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c           = null,
            Requested_Amount__c        = 500000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                  = 'Draft'
        );
        Test.startTest();
        DrawdownRequestValidationService.ValidationResult result =
            DrawdownRequestValidationService.validate(dr);
        Test.stopTest();
        Assert.isFalse(result.isValid, 'null Debt_Position__c must produce an invalid result');
        Assert.isFalse(result.errors.isEmpty(), 'Errors list must not be empty for null DP');
    }

    @IsTest
    static void testValidateFromFlow_ValidDR_ReturnsValidString() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Drawdown_Request__c dr = new Drawdown_Request__c(
            Debt_Position__c           = dp.Id,
            Requested_Amount__c        = 1000000,
            Requested_Drawdown_Date__c = Date.today().addDays(5),
            Status__c                  = 'Draft'
        );
        insert dr;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        List<String> results = DrawdownRequestValidationService.validateFromFlow(
            new List<Id>{ dr.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'validateFromFlow must return one result per request');
        // Availability_Period exists (from @TestSetup) and amount > 0 → VALID
        Assert.areEqual('VALID', results[0],
            'With availability period and positive amount, result must be VALID');
    }
}