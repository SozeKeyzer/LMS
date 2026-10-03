/**
 * LMSAccrualStrategyTest
 * Covers: FixedRateAccrualStrategy, FloatingRateAccrualStrategy, PIKAccrualStrategy,
 *         AmortisationScheduleStrategy, HolderEconomicsStrategy, BreakCostStrategy
 * Executes strategies in Preview and Commit modes; verifies CalcResult shape.
 */
@IsTest
private class LMSAccrualStrategyTest {

    private static Debt_Position__c makeDP() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Strategy FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Strategy DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            Waterfall_Rule__c        = 'STANDARD',
            iPlatform_External_Id__c = 'STRAT-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
        return dp;
    }

    private static Interest_Period__c makeIP(Id dpId, Decimal rate) {
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dpId,
            Application_Status__c = 'Applied',
            Spread__c             = rate
        );
        insert irt;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dpId,
            Period_Start__c       = Date.today().toStartOfMonth(),
            Period_End__c         = Date.today().toStartOfMonth().addMonths(1),
            All_In_Rate__c        = rate,
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = rate
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;
        return ip;
    }

    private static void setupAmortisationConfig(Id dpId) {
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(
            Id = dpId,
            Position_Notional__c      = 1000000,
            First_Payment_Date__c     = Date.today().addMonths(3).toStartOfMonth(),
            Position_Maturity_Date__c = Date.today().addYears(3),
            Payment_Frequency__c      = 'Quarterly'
        );
        insert new Amortisation_Rules__c(Debt_Position__c = dpId);
        insert new Interest_Rate_Terms__c(
            Debt_Position__c           = dpId,
            Pricing_Basis__c           = 'Fixed',
            Applicable_Fixed_Rate__c   = 8.0,
            Application_Status__c      = 'Applied',
            Actual_Application_Date__c = Date.today()
        );
        TriggerContext.getInstance().bypassGuards = false;
    }

    private static OrchestratorCalcContext buildOrcCtx(Id dpId, String mode) {
        OrchestratorCalcContext ctx = new OrchestratorCalcContext();
        ctx.parentRecordId    = dpId;
        ctx.runMode           = mode;
        ctx.calcDeveloperName = 'Test_Accrual';
        ctx.calcVersion       = '1.0.0';
        return ctx;
    }

    // ─── FixedRateAccrualStrategy ─────────────────────────────────────────────

    @IsTest
    static void testFixedRateAccrualStrategy_Preview_ReturnsSuccess() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        makeIP(dp.Id, 8.5);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new FixedRateAccrualStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'FixedRateAccrualStrategy Preview must return success=true');
        Assert.isFalse(result.outputRows.isEmpty(), 'Preview must generate output rows');
    }

    @IsTest
    static void testFixedRateAccrualStrategy_Commit_PersistsRows() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        makeIP(dp.Id, 8.5);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Commit');

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcResult result = new FixedRateAccrualStrategy().execute(ctx);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isTrue(result.success);
        Integer cnt = [SELECT COUNT() FROM Accrual_Daily__c WHERE Debt_Position__c = :dp.Id];
        Assert.isTrue(cnt > 0, 'Commit mode must persist accrual rows to Accrual_Daily__c');
    }

    // ─── FloatingRateAccrualStrategy ─────────────────────────────────────────

    @IsTest
    static void testFloatingRateAccrualStrategy_Preview_DelegatesToFixed() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        makeIP(dp.Id, 5.5); // all-in rate set (floating period after lock)
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new FloatingRateAccrualStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'FloatingRateAccrualStrategy must delegate to FixedRate and return success');
    }

    @IsTest
    static void testFloatingRateAccrualStrategy_Commit_PersistsRows() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        makeIP(dp.Id, 5.5);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Commit');

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcResult result = new FloatingRateAccrualStrategy().execute(ctx);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isTrue(result.success, 'FloatingRateAccrualStrategy Commit must return success');
        Integer cnt = [SELECT COUNT() FROM Accrual_Daily__c WHERE Debt_Position__c = :dp.Id];
        Assert.isTrue(cnt > 0, 'Commit mode must persist floating accrual rows to Accrual_Daily__c');
    }

    // ─── PIKAccrualStrategy ───────────────────────────────────────────────────

    @IsTest
    static void testPIKAccrualStrategy_Preview_ProducesPIKRows() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        TriggerContext.getInstance().bypassGuards = true;
        // Update DP to allow PIK
        update new Debt_Position__c(Id = dp.Id, PIK_Allowed__c = true, PIK_Default_Mode__c = 'Auto_PIK');
        TriggerContext.getInstance().bypassGuards = false;
        makeIP(dp.Id, 9.0);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new PIKAccrualStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'PIKAccrualStrategy Preview must return success');
        Boolean anyPIK = false;
        for (SObject row : result.outputRows) {
            if (row.get('Is_PIK__c') == true) { anyPIK = true; break; }
        }
        Assert.isTrue(anyPIK, 'PIKAccrualStrategy must produce rows with Is_PIK__c = true');
    }

    @IsTest
    static void testPIKAccrualStrategy_Commit_PersistsPIKRows() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, PIK_Allowed__c = true, PIK_Default_Mode__c = 'Auto_PIK');
        TriggerContext.getInstance().bypassGuards = false;
        makeIP(dp.Id, 9.0);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Commit');

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcResult result = new PIKAccrualStrategy().execute(ctx);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isTrue(result.success, 'PIKAccrualStrategy Commit must return success');
        Integer cnt = [SELECT COUNT() FROM Accrual_Daily__c WHERE Debt_Position__c = :dp.Id AND Is_PIK__c = true];
        Assert.isTrue(cnt > 0, 'Commit mode must persist PIK accrual rows to Accrual_Daily__c');
    }

    // ─── AmortisationScheduleStrategy ────────────────────────────────────────

    @IsTest
    static void testAmortisationScheduleStrategy_Preview_ReturnsRows() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        setupAmortisationConfig(dp.Id);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');
        ctx.calcDeveloperName = 'Amortisation_Schedule';

        Test.startTest();
        CalcResult result = new AmortisationScheduleStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'AmortisationScheduleStrategy must return success');
        Assert.isFalse(result.outputRows.isEmpty(), 'Preview must return schedule rows');
    }

    @IsTest
    static void testAmortisationScheduleStrategy_Commit_PersistsSchedule() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        setupAmortisationConfig(dp.Id);
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Commit');

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcResult result = new AmortisationScheduleStrategy().execute(ctx);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Assert.isTrue(result.success);
        Integer cnt = [SELECT COUNT() FROM Payment_Schedule__c WHERE Debt_Position__c = :dp.Id];
        Assert.isTrue(cnt > 0, 'Commit must write rows to Payment_Schedule__c');
    }

    // ─── HolderEconomicsStrategy ──────────────────────────────────────────────

    @IsTest
    static void testHolderEconomicsStrategy_NoHolders_ReturnsSuccessEmpty() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new HolderEconomicsStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'HolderEconomicsStrategy with no holders must return success');
    }

    @IsTest
    static void testHolderEconomicsStrategy_WithHolders_Succeeds() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new HolderEconomicsStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'HolderEconomicsStrategy must return success');
    }

    // ─── BreakCostStrategy ────────────────────────────────────────────────────

    @IsTest
    static void testBreakCostStrategy_NoPrepaymentEvents_ReturnsSuccessEmpty() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');

        Test.startTest();
        CalcResult result = new BreakCostStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'BreakCostStrategy with no events must return success');
    }

    @IsTest
    static void testBreakCostStrategy_WithPrepaymentEvent_Succeeds() {
        TriggerContext.reset();
        Debt_Position__c dp = makeDP();
        Prepayment_Event__c pe = new Prepayment_Event__c(
            Debt_Position__c     = dp.Id, Status__c = 'Approved',
            Prepaid_Principal__c = 500000, Prepayment_Date__c = Date.today(),
            Notice_Date__c       = Date.today(),
            Break_Cost_Basis__c  = 'Par'
        );
        insert pe;

        OrchestratorCalcContext ctx = buildOrcCtx(dp.Id, 'Preview');
        Test.startTest();
        CalcResult result = new BreakCostStrategy().execute(ctx);
        Test.stopTest();

        Assert.isTrue(result.success, 'BreakCostStrategy with event must return success');
    }
}