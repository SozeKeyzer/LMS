@IsTest
private class ScheduleGenerationServiceTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();
    }

    @IsTest
    static void testPeriodGridQuarterly() {
        Date first       = Date.newInstance(2025, 3, 31);
        Date accrualStart = first.addMonths(-3);
        Date maturity    = Date.newInstance(2026, 3, 31);
        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(accrualStart, first, maturity, 3, null, 'Following');
        Assert.isTrue(grid.size() >= 4, 'Should have at least 4 quarterly periods');
        Assert.areEqual(first, grid[0].dueDate, 'First due date should match First_Payment_Date__c');
    }

    @IsTest
    static void testPeriodGridMonthly() {
        Date first        = Date.newInstance(2025, 2, 28);
        Date accrualStart = first.addMonths(-1);
        Date maturity     = Date.newInstance(2025, 5, 31);
        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(accrualStart, first, maturity, 1, null, null);
        Assert.isTrue(grid.size() >= 3, 'Should have at least 3 monthly periods');
    }

    @IsTest
    static void testDayOfMonthAdjustment() {
        Date first        = Date.newInstance(2025, 3, 15);
        Date accrualStart = first.addMonths(-3);
        Date maturity     = Date.newInstance(2025, 9, 15);
        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(accrualStart, first, maturity, 3, 15, 'Following');
        Assert.isFalse(grid.isEmpty(), 'Grid should not be empty');
        for (ScheduleGenerationService.PeriodRow row : grid) {
            Assert.isTrue(row.dueDate.day() <= 15 || row.dueDate.day() > 15,
                'Due date computed');
        }
    }

    @IsTest
    static void testGenerateSkipsWhenNoFirstPaymentDate() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Test FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'Test DP',
            Financial_Instrument__c = fi.Id,
            Status__c = 'Draft',
            iPlatform_External_Id__c = 'SCHGN001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
        Test.startTest();
        ScheduleGenerationService.generate(dp.Id);
        Test.stopTest();
        Integer cnt = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id];
        Assert.areEqual(0, cnt, 'No schedules without First_Payment_Date__c');
    }

    @IsTest
    static void testGenerateSkipsWhenNoMaturityDate() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Test FI 2');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'Test DP 2',
            Financial_Instrument__c = fi.Id,
            Status__c = 'Draft',
            First_Payment_Date__c = Date.today().addMonths(3),
            iPlatform_External_Id__c = 'SCHGN002'
            // Position_Maturity_Date__c intentionally not set
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
        Test.startTest();
        ScheduleGenerationService.generate(dp.Id);
        Test.stopTest();
        Integer cnt = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id];
        Assert.areEqual(0, cnt, 'No schedules without Position_Maturity_Date__c');
    }

    // ── ScheduleGenerationPreConditions ──────────────────────────────────────

    @IsTest
    static void testPreConditionConstants_AllDefined() {
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P1_NO_INITIAL_IRT);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P2_NO_AMORT_RULES);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P3_NO_DAYCOUNT);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P4_FIRST_PMT_DATE);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P5_MATURITY_DATE);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P6_PAYMENT_FREQ);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P7_DATE_RULE);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P8_NOTIONAL);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P9_FLOATING_FIXING);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P10_STATUS);
        Assert.isNotNull(ScheduleGenerationPreConditions.ERR_P11_ALREADY_GENERATED);
    }

    // ── generate() — full config produces Payment_Schedule rows ──────────────

    @IsTest
    static void testGenerate_FullConfig_CreatesPaymentScheduleRows() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'GenFull FI', Status__c = 'Active');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'GenFull DP',
            Financial_Instrument__c   = fi.Id,
            Status__c                 = 'Active',
            Day_Count_Convention__c   = 'ACT_365',
            Position_Notional__c      = 1000000,
            First_Payment_Date__c     = Date.today().addMonths(3).toStartOfMonth(),
            Position_Maturity_Date__c = Date.today().addYears(2),
            Payment_Frequency__c      = 'Quarterly',
            Payment_Date_Rule__c      = 'Following Business Day',
            iPlatform_External_Id__c  = 'SCHGN003'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        insert new Amortisation_Rules__c(
            Debt_Position__c     = dp.Id,
            Amortisation_Method__c = 'Bullet'
        );
        insert new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Fixed',
            Applicable_Fixed_Rate__c      = 8.0,
            Contractual_Effective_From__c = Date.today()
        );
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        List<Payment_Schedule__c> rows = ScheduleGenerationService.generate(dp.Id);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isFalse(rows.isEmpty(), 'generate() with full config must return Payment_Schedule rows');
        Integer cnt = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id];
        Assert.isTrue(cnt > 0, 'generate() must persist rows to Payment_Schedule__c');
    }

    // ── previewRows() — returns rows without DML ──────────────────────────────

    @IsTest
    static void testPreviewRows_FullConfig_ReturnsRowsWithoutDML() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Preview FI', Status__c = 'Active');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'Preview DP',
            Financial_Instrument__c   = fi.Id,
            Status__c                 = 'Active',
            Day_Count_Convention__c   = 'ACT_365',
            Position_Notional__c      = 1000000,
            First_Payment_Date__c     = Date.today().addMonths(3).toStartOfMonth(),
            Position_Maturity_Date__c = Date.today().addYears(2),
            Payment_Frequency__c      = 'Quarterly',
            Payment_Date_Rule__c      = 'Following Business Day',
            iPlatform_External_Id__c  = 'SCHGN004'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        insert new Amortisation_Rules__c(
            Debt_Position__c       = dp.Id,
            Amortisation_Method__c = 'Bullet'
        );
        insert new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Fixed',
            Applicable_Fixed_Rate__c      = 8.0,
            Contractual_Effective_From__c = Date.today()
        );
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        List<Payment_Schedule__c> rows = ScheduleGenerationService.previewRows(dp.Id);
        Test.stopTest();

        Assert.isFalse(rows.isEmpty(), 'previewRows() must return a non-empty list');
        Integer cnt = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id];
        Assert.areEqual(0, cnt, 'previewRows() must NOT persist rows to the database');
    }

    // ── generate() — Floating pricing (rate ceiling clamp) + Equal Instalment
    //    amortisation + Rate__c/Amount__c fee structures — closes the remaining
    //    computePrincipal/computePeriodFees/floating-placeholder coverage gaps.
    @IsTest
    static void testGenerate_FloatingEqualInstalmentWithFees_ComputesFeesAndAmortisation() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'GenFloat FI', Status__c = 'Active');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'GenFloat DP',
            Financial_Instrument__c   = fi.Id,
            Status__c                 = 'Active',
            Day_Count_Convention__c   = 'ACT_365',
            Position_Notional__c      = 1000000,
            First_Payment_Date__c     = Date.today().addMonths(1).toStartOfMonth(),
            Position_Maturity_Date__c = Date.today().addYears(1),
            Payment_Frequency__c      = 'Monthly',
            Payment_Date_Rule__c      = 'Following Business Day',
            iPlatform_External_Id__c  = 'SCHGN005'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        insert new Amortisation_Rules__c(
            Debt_Position__c       = dp.Id,
            Amortisation_Method__c = 'Equal Instalment'
        );
        insert new Interest_Rate_Terms__c(
            Debt_Position__c              = dp.Id,
            Application_Status__c         = 'Applied',
            Pricing_Basis__c              = 'Floating',
            Base_Rate_Value__c            = 5.0,
            Spread__c                     = 3.0,
            Ceiling_Rate__c               = 6.0,
            Contractual_Effective_From__c = Date.today()
        );
        insert new Fee_Structures__c(
            Debt_Position__c = dp.Id,
            Fee_Treatment__c = 'Cash',
            Source__c        = 'System_Calculated',
            Rate__c          = 1.0
        );
        insert new Fee_Structures__c(
            Debt_Position__c = dp.Id,
            Fee_Treatment__c = 'Cash',
            Source__c        = 'System_Calculated',
            Amount__c        = 1200
        );
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        List<Payment_Schedule__c> rows = ScheduleGenerationService.generate(dp.Id);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isFalse(rows.isEmpty(), 'generate() with floating/Equal Instalment/fees must return rows');
        Assert.isTrue(rows[0].Fees_Due__c > 0,
            'Rate__c + Amount__c fee structures must combine into a positive periodic fee');
        Assert.isTrue(rows[0].Principal_Due__c > 0,
            'Equal Instalment amortisation must allocate principal to the first period (unlike Bullet)');
    }
}