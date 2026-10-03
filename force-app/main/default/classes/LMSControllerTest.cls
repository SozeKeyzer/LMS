/**
 * LMSControllerTest
 * Covers: All @AuraEnabled controllers — blank/invalid input returns empty/null gracefully,
 *         valid input returns correctly shaped DTOs.
 * Uses with sharing + USER_MODE enforcement, so minimal data setup is sufficient for smoke tests.
 */
@IsTest
private class LMSControllerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Ctrl FI', Status__c = 'Active');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Ctrl DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            iPlatform_External_Id__c = 'CTRL-0001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        // One audit event for correlation tests
        Audit_Event__c ae = new Audit_Event__c(
            Correlation_Id__c   = 'ctrl-corr-1',
            Event_Type__c       = 'RECORD_CREATED',
            Actor_System__c     = 'User',
            Source_Record_Id__c = String.valueOf(dp.Id),
            Event_DateTime__c   = Datetime.now(),
            Source_Object__c    = 'Debt_Position__c',
            Source__c           = 'System_Calculated'
        );
        insert ae;
    }

    // ─── AuditEventController ────────────────────────────────────────────────

    @IsTest
    static void testAuditEventController_BlankCorrelationId_ReturnsEmpty() {
        Test.startTest();
        List<AuditEventController.AuditEventDTO> result =
            AuditEventController.getAuditEventsByCorrelationId('');
        Test.stopTest();
        Assert.isTrue(result == null || result.isEmpty(), 'Blank correlation ID must return empty list');
    }

    @IsTest
    static void testAuditEventController_MatchingCorrelationId_ReturnsDTOs() {
        Test.startTest();
        List<AuditEventController.AuditEventDTO> result =
            AuditEventController.getAuditEventsByCorrelationId('ctrl-corr-1');
        Test.stopTest();
        Assert.isFalse(result.isEmpty(), 'Matching correlation ID must return DTO list');
        Assert.areEqual('RECORD_CREATED', result[0].eventType);
    }

    // ─── DebtPositionKpiController ────────────────────────────────────────────

    @IsTest
    static void testDebtPositionKpiController_ReturnsKpiDTO() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        DebtPositionKpiController.KpiDTO dto = DebtPositionKpiController.getKpis(dp.Id);
        Test.stopTest();
        Assert.isNotNull(dto, 'getKpis must return a non-null DTO');
        Assert.isNotNull(dto.outstandingFormatted, 'KpiDTO must populate outstandingFormatted');
    }

    // ─── CashflowChartController ──────────────────────────────────────────────

    @IsTest
    static void testCashflowChartController_AggregateMode_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            List<CashflowChartController.CashflowDTO> result =
                CashflowChartController.getCashflows(fi.Id, 'Aggregate');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getCashflows aggregate mode must not throw');
    }

    @IsTest
    static void testCashflowChartController_PositionMode_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            List<CashflowChartController.CashflowDTO> result =
                CashflowChartController.getCashflows(dp.Id, 'Position');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getCashflows position mode must not throw');
    }

    // ─── DealCockpitController ────────────────────────────────────────────────

    @IsTest
    static void testDealCockpitController_GetSummary_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            DealCockpitController.DealSummaryDTO dto = DealCockpitController.getSummary(fi.Id);
            Assert.isNotNull(dto, 'getSummary must return a non-null DTO');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'DealCockpitController.getSummary must not throw');
    }

    // ─── ExceptionsInboxController ────────────────────────────────────────────

    @IsTest
    static void testExceptionsInboxController_GetExceptions_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            List<ExceptionsInboxController.ExceptionItemDTO> excs = ExceptionsInboxController.getExceptions();
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getExceptions must not throw');
    }

    // ─── CalcReadinessController ──────────────────────────────────────────────

    @IsTest
    static void testCalcReadinessController_GetReadiness_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            List<CalcReadinessController.ReadinessDTO> dtos = CalcReadinessController.getReadiness(dp.Id, 'Debt_Position__c');
            Assert.isNotNull(dtos);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getReadiness must not throw');
    }

    @IsTest
    static void testCalcReadinessController_Preview_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            CalcReadinessController.preview(dp.Id, null);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'preview() must not throw');
    }

    // ─── CalcRunHistoryController ─────────────────────────────────────────────

    @IsTest
    static void testCalcRunHistoryController_GetRunsDP_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            List<Calculation_Run__c> runs = CalcRunHistoryController.getRuns(dp.Id, 'DP');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getRuns(DP mode) must not throw');
    }

    @IsTest
    static void testCalcRunHistoryController_GetRunsFI_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            // Must pass the exact API name to hit the FI branch in CalcRunHistoryController
            List<Calculation_Run__c> runs = CalcRunHistoryController.getRuns(fi.Id, 'Financial_Instrument__c');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getRuns(Financial_Instrument__c mode) must not throw');
    }

    // ─── HolderEconomicsController ────────────────────────────────────────────

    @IsTest
    static void testHolderEconomicsController_GetHolders_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            List<HolderEconomicsController.HolderDTO> holders = HolderEconomicsController.getHolders(fi.Id, 'aggregate');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getHolders must not throw');
    }

    // ─── ShadowComparisonController ───────────────────────────────────────────

    @IsTest
    static void testShadowComparisonController_GetComparisons_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            List<Calculation_Shadow_Comparison__c> results = ShadowComparisonController.getComparisons('');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getComparisons must not throw');
    }

    // ─── RateApplicationConfirmController ────────────────────────────────────

    @IsTest
    static void testRateApplicationConfirmController_GetEventDetails_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending', Spread__c = 2.5
        );
        insert irt;
        Rate_Application_Event__c rae = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id, Decision_Type__c = null,
            Decision_Date__c = Date.today(), Reason__c = 'Test reason'
        );
        insert rae;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Map<String,Object> dto = null;
        try {
            dto = RateApplicationConfirmController.getEventDetails(rae.Id);
        } catch (Exception e) {
            Assert.fail('getEventDetails threw ' + e.getTypeName() + ': ' + e.getMessage());
        }
        Test.stopTest();
        Assert.isNotNull(dto, 'getEventDetails must return a non-null result for a valid RAE Id');
    }

    @IsTest
    static void testRateApplicationConfirmController_SubmitDecision_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending', Spread__c = 3.0
        );
        insert irt;
        Rate_Application_Event__c rae = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id, Decision_Type__c = null,
            Decision_Date__c = Date.today(), Reason__c = 'Test reason'
        );
        insert rae;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean threw = false;
        try {
            RateApplicationConfirmController.submitDecision(rae.Id, 'Apply', 'submit-test', Date.today());
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'submitDecision must not throw for valid Apply decision');
    }

    // ─── CascadePreviewController ─────────────────────────────────────────────

    @IsTest
    static void testCascadePreviewController_Preview_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            CascadePreviewController.CascadePreviewDTO result =
                CascadePreviewController.preview(dp.Id, 'Debt_Position__c', null, null);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'preview() must not throw');
    }

    // ─── AmendmentProjectionComparisonController ──────────────────────────────

    @IsTest
    static void testAmendmentProjectionComparisonController_GeneratePreview_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentProjectionComparisonController.generatePreview(dp.Id);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'generatePreview must not throw');
    }

    @IsTest
    static void testAmendmentProjectionComparisonController_GetScheduleComparison_NullId() {
        Test.startTest();
        Object result = AmendmentProjectionComparisonController.getScheduleComparison(null);
        Test.stopTest();
        Assert.isNotNull(result, 'getScheduleComparison(null) must return an empty result, not null');
    }

    @IsTest
    static void testAmendmentProjectionComparisonController_GetScheduleComparison_WithLA_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c dp        = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Loan_Amendment__c la = new Loan_Amendment__c(
            Scope__c                   = 'Position',
            Amendment_Type__c          = 'Rate_Change',
            Status__c                  = 'Draft',
            Debt_Position__c           = dp.Id,
            Financial_Instrument__c    = fi.Id,
            Proposed_Effective_Date__c = Date.today().addDays(30)
        );
        insert la;
        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentProjectionComparisonController.getScheduleComparison(la.Id);
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'getScheduleComparison with valid LA must not throw');
    }

    // Facility scope (resolveDpIds' Financial_Instrument__c branch) + Actual_Effective_Date set
    // (ternary true branch) + a linked Projection with Projected_Rows__c JSON (queryProjectionSummary
    // / parseProjectedRows / strToDate / toDecimal) — closes the remaining coverage gaps left by
    // the Position-scope, no-projection test above.
    @IsTest
    static void testAmendmentProjectionComparisonController_GetScheduleComparison_FacilityScopeWithProjection() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c dp        = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Projection__c proj = new Projection__c(
            Debt_Position__c   = dp.Id,
            Status__c          = 'Generated',
            Projection_Type__c = 'Amendment_Preview',
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'proj-facility-test',
            Projected_Rows__c  = '[{"periodStart":"2026-01-01","periodEnd":"2026-01-31",'
                + '"dueDate":"2026-02-01","principalDue":"1000.50","interestDue":"200.25",'
                + '"totalDue":"1200.75","status":"Projected"}]'
        );
        insert proj;

        Loan_Amendment__c la = new Loan_Amendment__c(
            Scope__c                   = 'Facility',
            Amendment_Type__c          = 'Rate_Change',
            Status__c                  = 'Draft',
            Financial_Instrument__c    = fi.Id,
            Proposed_Effective_Date__c = Date.today().addDays(30),
            Actual_Effective_Date__c   = Date.today(),
            Recalc_Projection__c       = proj.Id
        );
        insert la;

        Test.startTest();
        AmendmentProjectionComparisonController.ComparisonResult result =
            AmendmentProjectionComparisonController.getScheduleComparison(la.Id);
        Test.stopTest();

        Assert.areEqual('Facility', result.scope, 'Facility scope must resolve DPs via Financial_Instrument__c');
        Assert.isNotNull(result.projectionSummary, 'Linked Recalc_Projection must populate projectionSummary');
        Assert.areEqual(1, result.projectionSummary.projectedRows.size(),
            'Projected_Rows__c JSON must be parsed into one ProjectedRow');
        Assert.areEqual(1000.50, result.projectionSummary.projectedRows[0].principalDue,
            'principalDue must be parsed from the JSON string value');
        Assert.areEqual(Date.newInstance(2026, 1, 1), result.projectionSummary.projectedRows[0].periodStart,
            'periodStart must be parsed from the JSON date string');
    }

    // ─── ShadowComparisonController — non-blank calcDeveloperName ────────────

    @IsTest
    static void testShadowComparisonController_NonBlankCalcName_FiltersResults() {
        Calculation_Shadow_Comparison__c comp = new Calculation_Shadow_Comparison__c(
            Calc_Definition__c      = 'Test_Shadow_Calc',
            Status__c               = 'Pending_Review',
            Locked_Version__c       = '1.0.0',
            Proposed_Version__c     = '1.0.1',
            Differences_Detected__c = false,
            Difference_Summary__c   = 'smoke test',
            Parent_Record_Id__c     = 'TESTID001'
        );
        insert comp;
        Test.startTest();
        List<Calculation_Shadow_Comparison__c> results =
            ShadowComparisonController.getComparisons('Test_Shadow_Calc');
        Test.stopTest();
        Assert.isFalse(results.isEmpty(), 'Non-blank calcDeveloperName must return matching records');
        Assert.areEqual('Test_Shadow_Calc', results[0].Calc_Definition__c);
    }

    // ─── DebtPositionKpiController — with actual accrual and schedule data ─────

    @IsTest
    static void testDebtPositionKpiController_WithSchedule_PopulatesUpcomingPayment() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        // Upcoming payment schedule to cover the non-empty upcoming branch (lines 44-49)
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Status__c         = 'Due',
            Principal_Due__c  = 100000,
            Interest_Due__c   = 5000,
            Fees_Due__c       = 0,
            Net_Due__c        = 105000,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'CTRL-KPI-UPCOM-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        DebtPositionKpiController.KpiDTO dto = DebtPositionKpiController.getKpis(dp.Id);
        Test.stopTest();

        Assert.isNotNull(dto, 'getKpis must return non-null DTO');
        Assert.areNotEqual('—', dto.nextPaymentFormatted,
            'nextPaymentFormatted must be populated when an upcoming schedule row exists');
        Assert.isNotNull(dto.nextPaymentDate, 'nextPaymentDate must be populated');
    }

    // ─── CashflowChartController — with actual Payment_Schedule data ──────────

    @IsTest
    static void testCashflowChartController_PositionMode_WithScheduleData_ReturnsDTO() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Status__c         = 'Projected',
            Principal_Due__c  = 100000,
            Interest_Due__c   = 8000,
            Fees_Due__c       = 500,
            Net_Due__c        = 108500,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'CTRL-CHART-PS-001'
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        List<CashflowChartController.CashflowDTO> dtos =
            CashflowChartController.getCashflows(dp.Id, 'Position');
        Test.stopTest();
        Assert.isFalse(dtos.isEmpty(), 'Position mode with PS data must return at least one DTO');
        Assert.areEqual(100000, dtos[0].principal);
        Assert.areEqual(8000,   dtos[0].interest);
    }

    // ─── CascadePreviewController.commitCascade ───────────────────────────────

    @IsTest
    static void testCascadePreviewController_CommitCascade_CreatesCascadeRun() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Test.startTest();
        String jsonResult = CascadePreviewController.commitCascade(
            dp.Id, 'Debt_Position__c', 'Status__c', 'Active', 'Test reason', 'Test explanation');
        Test.stopTest();
        Assert.isNotNull(jsonResult, 'commitCascade must return serialised JSON');
        Integer cnt = [SELECT COUNT() FROM Cascade_Run__c
                       WHERE Triggering_Object__c = 'Debt_Position__c'];
        Assert.areEqual(1, cnt, 'commitCascade must create one Cascade_Run__c');
    }
}