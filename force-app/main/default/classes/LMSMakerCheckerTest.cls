/**
 * LMSMakerCheckerTest
 * Covers ScheduleGenerationPreConditions (11 gate checks) and
 * PaymentScheduleService maker-checker methods (generateDraft, submitForReview, approve, reject).
 * Spec v3 Part 6.5.
 */
@IsTest
private class LMSMakerCheckerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();
    }

    // Build a fully-qualified DP that passes all 11 pre-conditions
    private static Debt_Position__c buildQualifiedDP() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'MakerChecker FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                          = 'MakerChecker DP',
            Financial_Instrument__c       = fi.Id,
            Status__c                     = 'Draft',
            Position_Notional__c          = 5000000,
            Day_Count_Convention__c       = 'ACT_365',
            First_Payment_Date__c         = Date.today().addMonths(3),
            Accrual_Start_Date__c         = Date.today(),
            Position_Maturity_Date__c     = Date.today().addYears(5),
            Payment_Frequency__c          = 'Quarterly',
            Payment_Date_Rule__c          = 'Following Business Day',
            Schedule_Generation_Status__c = null,
            Rate_Type__c                  = 'Fixed',
            iPlatform_External_Id__c      = 'MKCHK-001'
        );
        insert dp;

        // P1: Applied IRT
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c    = dp.Id,
            Application_Status__c = 'Applied'
        );
        insert irt;

        // P2: Amortisation_Rules exists for the DP
        Amortisation_Rules__c ar = new Amortisation_Rules__c(
            Debt_Position__c = dp.Id
        );
        insert ar;

        return [SELECT Id FROM Debt_Position__c WHERE Id = :dp.Id];
    }

    // ── ScheduleGenerationPreConditions ──────────────────────────────────────

    // Fully qualified DP → no failures
    @IsTest
    static void testPreConditions_AllPass_NoFailures() {
        Debt_Position__c dp = buildQualifiedDP();
        Test.startTest();
        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Test.stopTest();
        Assert.isTrue(failures.isEmpty(), 'Fully qualified DP should have zero pre-condition failures. Got: ' + failures);
    }

    // P3: Missing day count convention
    @IsTest
    static void testPreConditions_P3_MissingDayCount() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Day_Count_Convention__c = null);
        TriggerContext.getInstance().bypassGuards = false;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.contains(ScheduleGenerationPreConditions.ERR_P3_NO_DAYCOUNT),
            'P3 failure expected when Day_Count_Convention__c is null');
    }

    // P4: First payment date before accrual start
    @IsTest
    static void testPreConditions_P4_InvalidFirstPaymentDate() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id,
            Accrual_Start_Date__c = Date.today().addYears(1),
            First_Payment_Date__c = Date.today()); // before accrual start
        TriggerContext.getInstance().bypassGuards = false;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.contains(ScheduleGenerationPreConditions.ERR_P4_FIRST_PMT_DATE), 'P4 failure expected');
    }

    // P8: Zero notional
    @IsTest
    static void testPreConditions_P8_ZeroNotional() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Position_Notional__c = 0);
        TriggerContext.getInstance().bypassGuards = false;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.contains(ScheduleGenerationPreConditions.ERR_P8_NOTIONAL), 'P8 failure expected for zero notional');
    }

    // P10: Status = Active (already active)
    @IsTest
    static void testPreConditions_P10_StatusActive() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Status__c = 'Active');
        TriggerContext.getInstance().bypassGuards = false;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.contains(ScheduleGenerationPreConditions.ERR_P10_STATUS), 'P10 failure expected for Active status');
    }

    // P11: Schedule already generated (not Not_Generated)
    @IsTest
    static void testPreConditions_P11_ScheduleAlreadyGenerated() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Status__c = 'Draft');
        TriggerContext.getInstance().bypassGuards = false;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.contains(ScheduleGenerationPreConditions.ERR_P11_ALREADY_GENERATED),
            'P11 failure expected when schedule is Draft');
    }

    // Multiple failures accumulate
    @IsTest
    static void testPreConditions_MultipleFailures_AllReturned() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'BadFI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'Bad DP', Financial_Instrument__c = fi.Id, Status__c = 'Active',
            Position_Notional__c = 0, Day_Count_Convention__c = null,
            iPlatform_External_Id__c = 'MKCHK-001'
        );
        insert dp;

        List<String> failures = ScheduleGenerationPreConditions.validate(dp.Id);
        Assert.isTrue(failures.size() >= 4, 'Missing IRT, amort rules, daycount, notional, and wrong status should all fail. Got: ' + failures.size());
    }

    // ── PaymentScheduleService maker-checker ─────────────────────────────────

    // generateDraft: pre-condition failure → ScheduleGenerationException thrown
    @IsTest
    static void testGenerateDraft_PreConditionFailure_ThrowsException() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'BadDraft FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'BadDraft', Financial_Instrument__c = fi.Id, Status__c = 'Draft',
            Position_Notional__c = 0, // P8 will fail
            iPlatform_External_Id__c = 'MKCHK-001'
        );
        insert dp;

        Boolean threw = false;
        try {
            PaymentScheduleService.generateDraft(dp.Id, UserInfo.getUserId());
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            threw = true;
        }
        Assert.isTrue(threw, 'generateDraft must throw when pre-conditions not met');
    }

    // submitForReview: wrong status → exception
    @IsTest
    static void testSubmitForReview_WrongStatus_ThrowsException() {
        Debt_Position__c dp = buildQualifiedDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Status__c = 'Active');
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        try {
            PaymentScheduleService.submitForReview(dp.Id, UserInfo.getUserId(), 'notes');
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            threw = true;
            Assert.isTrue(ex.getMessage().contains('not in Draft status'));
        }
        Assert.isTrue(threw);
    }

    // approve: 4-eyes — checker = maker → exception
    @IsTest
    static void testApprove_SameUserAsMaker_ThrowsFourEyesViolation() {
        Debt_Position__c dp = buildQualifiedDP();
        Id makerId = UserInfo.getUserId();

        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id,
            Schedule_Generation_Status__c = 'Pending_Review',
            Schedule_Generation_Maker__c  = makerId);
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        try {
            PaymentScheduleService.approve(dp.Id, makerId, 'approved'); // same user!
        } catch (PaymentScheduleService.ScheduleGenerationException ex) {
            threw = true;
            Assert.isTrue(ex.getMessage().contains('4-eyes'), '4-eyes violation message expected');
        }
        Assert.isTrue(threw, 'Should throw when checker = maker');
    }

    // reject: resets status to Not_Generated, deletes Draft rows, records reason
    @IsTest
    static void testReject_ResetsStatusAndDeletesDraftRows() {
        Debt_Position__c dp = buildQualifiedDP();
        Id makerId = UserInfo.getUserId();

        // Create a Draft row representing the maker's submission
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Status__c         = 'Draft',
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Is_Immutable__c   = false,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert ps;
        update new Debt_Position__c(Id = dp.Id,
            Schedule_Generation_Status__c = 'Pending_Review',
            Schedule_Generation_Maker__c  = makerId);
        TriggerContext.getInstance().bypassGuards = false;

        // Use null as the maker so the current user (checker) != maker
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Maker__c = null);
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        PaymentScheduleService.reject(dp.Id, makerId, 'Not approved — missing collateral');
        Test.stopTest();

        Debt_Position__c dpAfter = [
            SELECT Schedule_Generation_Status__c, Schedule_Last_Reject_Reason__c
            FROM Debt_Position__c WHERE Id = :dp.Id
        ];
        Assert.areEqual('Not_Generated', dpAfter.Schedule_Generation_Status__c);
        Assert.areEqual('Not approved — missing collateral', dpAfter.Schedule_Last_Reject_Reason__c);

        Integer remainingRows = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id AND Status__c = 'Draft'];
        Assert.areEqual(0, remainingRows, 'Draft rows must be deleted on rejection');
    }

    // approve: correct user different from maker → sets Active and records checker
    @IsTest
    static void testApprove_ValidChecker_SetsActiveAndRecordsChecker() {
        Debt_Position__c dp = buildQualifiedDP();
        Id checkerId = UserInfo.getUserId();

        // Use null as the maker so the current user (checker) != maker
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id,
            Schedule_Generation_Status__c = 'Pending_Review',
            Schedule_Generation_Maker__c  = null);
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        PaymentScheduleService.approve(dp.Id, checkerId, 'LGTM');
        Test.stopTest();

        Debt_Position__c dpAfter = [
            SELECT Schedule_Generation_Status__c, Schedule_Generation_Checker__c, Schedule_Activated_DateTime__c
            FROM Debt_Position__c WHERE Id = :dp.Id
        ];
        Assert.areEqual('Active', dpAfter.Schedule_Generation_Status__c);
        Assert.areEqual(checkerId, dpAfter.Schedule_Generation_Checker__c);
        Assert.isNotNull(dpAfter.Schedule_Activated_DateTime__c);
    }

    // approve: Draft rows are promoted to Due/Paid and locked (Spec Part 5.2.1.2)
    @IsTest
    static void testApprove_PromotesRowsToDueOrPaidAndLocksThem() {
        Debt_Position__c dp = buildQualifiedDP();
        Id checkerId = UserInfo.getUserId();

        Payment_Schedule__c pastRow = new Payment_Schedule__c(
            Debt_Position__c = dp.Id,
            Period_Start__c  = Date.today().addMonths(-3),
            Period_End__c    = Date.today().addDays(-1),
            Due_Date__c      = Date.today().addDays(-1),
            Status__c        = 'Draft',
            Principal_Due__c = 0, Interest_Due__c = 0, Fees_Due__c = 0,
            Is_Immutable__c  = false,
            Source__c        = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c   = String.valueOf(dp.Id) + '-past'
        );
        Payment_Schedule__c futureRow = new Payment_Schedule__c(
            Debt_Position__c = dp.Id,
            Period_Start__c  = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Due_Date__c      = Date.today().addMonths(3),
            Status__c        = 'Draft',
            Principal_Due__c = 0, Interest_Due__c = 0, Fees_Due__c = 0,
            Is_Immutable__c  = false,
            Source__c        = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c   = String.valueOf(dp.Id) + '-future'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert new List<Payment_Schedule__c>{ pastRow, futureRow };
        update new Debt_Position__c(Id = dp.Id,
            Schedule_Generation_Status__c = 'Pending_Review',
            Schedule_Generation_Maker__c  = null);
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        PaymentScheduleService.approve(dp.Id, checkerId, 'LGTM');
        Test.stopTest();

        Map<Id, Payment_Schedule__c> rowsAfter = new Map<Id, Payment_Schedule__c>([
            SELECT Status__c, Is_Immutable__c FROM Payment_Schedule__c
            WHERE Id IN (:pastRow.Id, :futureRow.Id)
        ]);
        Assert.areEqual('Paid', rowsAfter.get(pastRow.Id).Status__c, 'Past period should be Paid');
        Assert.isTrue(rowsAfter.get(pastRow.Id).Is_Immutable__c);
        Assert.areEqual('Due', rowsAfter.get(futureRow.Id).Status__c, 'Future period should be Due');
        Assert.isTrue(rowsAfter.get(futureRow.Id).Is_Immutable__c);
    }
}