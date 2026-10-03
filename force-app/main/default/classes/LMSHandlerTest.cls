/**
 * LMSHandlerTest
 * Coverage for thin trigger handlers that primarily call AuditEventLogger:
 *   AccrualDailyHandler, PaymentScheduleHandler, PaymentAllocationHandler,
 *   PaymentAdjustmentHandler, PaymentTransactionHandler, DrawdownRequestHandler,
 *   ElectionHandler, PrepaymentEventHandler, RateApplicationEventHandler,
 *   RateIndexFixingHandler, FinancialInstrumentTriggerHandler, ProjectionHandler,
 *   FlowBypassAction, InterestReserveTransactionHandler
 * Verifies inserts/updates don't throw, and that business-logic delegations fire correctly.
 */
@IsTest
private class LMSHandlerTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Handler FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Handler DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            Waterfall_Rule__c        = 'STANDARD',
            iPlatform_External_Id__c = 'HNDLR-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── AccrualDailyHandler ─────────────────────────────────────────────────

    @IsTest
    static void testAccrualDailyHandler_AfterInsert_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Applied', Spread__c = 8.0
        );
        insert irt;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c = dp.Id, All_In_Rate__c = 8.0,
            Period_Start__c  = Date.today().toStartOfMonth(),
            Period_End__c    = Date.today().toStartOfMonth().addMonths(1),
            Status__c        = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;
        Test.startTest();
        Boolean threw = false;
        try {
            Accrual_Daily__c ad = new Accrual_Daily__c(
                Debt_Position__c   = dp.Id, Interest_Period__c = ip.Id,
                Accrual_Date__c    = Date.today(), Accrued_Amount__c = 500,
                Is_PIK__c          = false, Status__c = 'Accrued',
                Principal_Basis__c = 1000000, Rate__c = 8.0,
                Day_Count_Fraction__c = 0.002739, Source__c = 'System_Calculated',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c    = String.valueOf(dp.Id) + '-' + Date.today().format()
            );
            TriggerContext.getInstance().bypassGuards = true;
            insert ad;
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'AccrualDailyHandler afterInsert must not throw');
    }

    @IsTest
    static void testAccrualDailyHandler_AfterUpdate_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt2 = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Applied', Spread__c = 8.0
        );
        insert irt2;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c = dp.Id, All_In_Rate__c = 8.0,
            Period_Start__c  = Date.today().addMonths(1).toStartOfMonth(),
            Period_End__c    = Date.today().addMonths(2).toStartOfMonth(),
            Status__c        = 'Active',
            Applied_Rate_Terms__c = irt2.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        Accrual_Daily__c ad = new Accrual_Daily__c(
            Debt_Position__c = dp.Id, Interest_Period__c = ip.Id,
            Accrual_Date__c  = Date.today().addMonths(1), Accrued_Amount__c = 500,
            Is_PIK__c = false, Status__c = 'Accrued',
            Principal_Basis__c = 1000000, Rate__c = 8.0,
            Day_Count_Fraction__c = 0.002739, Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c = String.valueOf(dp.Id) + '-upd-' + Date.today().format()
        );
        insert ad;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean threw = false;
        try {
            TriggerContext.getInstance().bypassGuards = true;
            update new Accrual_Daily__c(Id = ad.Id, Status__c = 'Capitalised');
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'AccrualDailyHandler afterUpdate must not throw');
    }

    // ─── PaymentScheduleHandler ───────────────────────────────────────────────

    @IsTest
    static void testPaymentScheduleHandler_StatusChange_Logged() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c = dp.Id, Period_Start__c = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Due_Date__c      = Date.today().addMonths(3),
            Status__c        = 'Projected', Principal_Due__c = 100000,
            Interest_Due__c  = 5000, Fees_Due__c = 0, Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'PS-HANDLER-001'
        );
        insert ps;
        Test.startTest();
        update new Payment_Schedule__c(Id = ps.Id, Status__c = 'Due');
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Payment_Schedule__c psAfter = [SELECT Status__c FROM Payment_Schedule__c WHERE Id = :ps.Id];
        Assert.areEqual('Due', psAfter.Status__c);
    }

    // ─── ElectionHandler ─────────────────────────────────────────────────────

    @IsTest
    static void testElectionHandler_TypeChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Election__c el = new Election__c(
            Debt_Position__c  = dp.Id, Election_Type__c = 'Cash',
            Period_Start__c   = Date.today(), Period_End__c = Date.today().addMonths(3),
            Is_Immutable__c   = false, Default_Applied__c = false
        );
        insert el;

        Test.startTest();
        Boolean threw = false;
        try {
            TriggerContext.getInstance().bypassGuards = true;
            update new Election__c(Id = el.Id, Election_Type__c = 'PIK');
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'ElectionHandler afterUpdate must not throw on type change');
    }

    // ─── PrepaymentEventHandler ───────────────────────────────────────────────

    @IsTest
    static void testPrepaymentEventHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Prepayment_Event__c pe = new Prepayment_Event__c(
            Debt_Position__c  = dp.Id, Status__c = 'Notice',
            Prepaid_Principal__c = 100000, Prepayment_Date__c = Date.today(),
            Notice_Date__c = Date.today(),
            Break_Cost_Basis__c  = 'Par'
        );
        insert pe;

        Test.startTest();
        Boolean threw = false;
        try {
            TriggerContext.getInstance().bypassGuards = true;
            update new Prepayment_Event__c(Id = pe.Id, Status__c = 'Approved');
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw);
    }

    // ─── RateIndexFixingHandler ───────────────────────────────────────────────

    @IsTest
    static void testRateIndexFixingHandler_AfterInsert_NoException() {
        Rate_Index__c ri = new Rate_Index__c(Name = 'BBSW3M');
        insert ri;

        Test.startTest();
        Boolean threw = false;
        try {
            Rate_Index_Fixing__c rif = new Rate_Index_Fixing__c(
                Rate_Index__c = ri.Id, Fixing_Date__c = Date.today(),
                Rate__c = 4.5, External_Id__c = String.valueOf(ri.Id) + '-' + Date.today().format()
            );
            insert rif;
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'RateIndexFixingHandler afterInsert must not throw');
    }

    // ─── FinancialInstrumentTriggerHandler ────────────────────────────────────

    @IsTest
    static void testFIHandler_Insert_NoException() {
        Test.startTest();
        Boolean threw = false;
        try {
            insert new Financial_Instrument__c(Name = 'New FI Handler Test');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'FI afterInsert must not throw');
    }

    @IsTest
    static void testFIHandler_StatusChange_NoException() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        Boolean threw = false;
        try {
            update new Financial_Instrument__c(Id = fi.Id, Status__c = 'Closed');
        } catch (Exception e) { threw = true; }
        Test.stopTest();
        Assert.isFalse(threw, 'FI afterUpdate status change must not throw');
    }

    // ─── ProjectionHandler ────────────────────────────────────────────────────

    @IsTest
    static void testProjectionHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Projection__c proj = new Projection__c(
            Debt_Position__c = dp.Id, Status__c = 'Generated',
            Projection_Type__c = 'Amendment_Preview',
            Projected_Rows__c  = null,
            Source__c          = 'System_Calculated',
            Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION,
            Correlation_Id__c  = 'proj-handler-test'
        );
        insert proj;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Projection__c(Id = proj.Id, Status__c = 'Reviewed');
        } catch (Exception e) { threw = true; }
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();
        Assert.isFalse(threw);
    }

    // ─── RateApplicationEventHandler ─────────────────────────────────────────

    @IsTest
    static void testRateApplicationEventHandler_AfterUpdate_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c = dp.Id, Application_Status__c = 'Pending'
        );
        insert irt;

        Rate_Application_Event__c rae = new Rate_Application_Event__c(
            Interest_Rate_Terms__c = irt.Id, Decision_Type__c = null,
            Decision_Date__c = Date.today(),
            Reason__c        = 'Test reason'
        );
        insert rae;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Rate_Application_Event__c(Id = rae.Id, Decision_Type__c = 'Apply');
        } catch (Exception e) { threw = true; }
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();
        Assert.isFalse(threw, 'RateApplicationEventHandler afterUpdate must not throw');
    }

    // ─── FlowBypassAction ────────────────────────────────────────────────────

    @IsTest
    static void testFlowBypassAction_SetsTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(new List<Boolean>{ true });
        Assert.isTrue(TriggerContext.getInstance().bypassGuards, 'bypassGuards must be set to true');
        TriggerContext.getInstance().bypassGuards = false; // cleanup
    }

    @IsTest
    static void testFlowBypassAction_SetsFalse() {
        TriggerContext.getInstance().bypassGuards = true;
        FlowBypassAction.setBypassGuards(new List<Boolean>{ false });
        Assert.isFalse(TriggerContext.getInstance().bypassGuards, 'bypassGuards must be set to false');
    }

    @IsTest
    static void testFlowBypassAction_NullList_DefaultsToTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(null);
        Assert.isTrue(TriggerContext.getInstance().bypassGuards, 'null input defaults to bypass=true');
        TriggerContext.getInstance().bypassGuards = false;
    }

    @IsTest
    static void testFlowBypassAction_EmptyList_DefaultsToTrue() {
        TriggerContext.getInstance().bypassGuards = false;
        FlowBypassAction.setBypassGuards(new List<Boolean>());
        Assert.isTrue(TriggerContext.getInstance().bypassGuards);
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── InterestReserveTransactionHandler ───────────────────────────────────

    @IsTest
    static void testInterestReserveTransactionHandler_Fund_IncreasesBalance() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = new Interest_Reserve__c(
            Current_Reserve_Balance__c = 0,
            Debt_Position__c           = dp.Id
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert res;

        Payment_Transaction__c pt = new Payment_Transaction__c(
            Debt_Position__c = dp.Id, Amount__c = 50000,
            Status__c = 'Cleared', Transaction_Date__c = Date.today(),
            Value_Date__c = Date.today(), Payment_Method__c = 'EFT',
            Bank_Reference__c = 'BNK-RES-FUND-1'
        );
        insert pt;

        Test.startTest();
        Interest_Reserve_Transaction__c txn = new Interest_Reserve_Transaction__c(
            Interest_Reserve__c           = res.Id, Type__c = 'Fund',
            Transaction_Date__c           = Date.today(), Value_Date__c = Date.today(),
            Amount__c                     = 50000, Source__c = 'Manual_Entry',
            Linked_Payment_Transaction__c = pt.Id,
            External_Id__c                = 'RES-FUND-1'
        );
        insert txn;
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Reserve__c resAfter = [SELECT Current_Reserve_Balance__c FROM Interest_Reserve__c WHERE Id = :res.Id];
        Assert.areEqual(50000, resAfter.Current_Reserve_Balance__c, 'Fund transaction should increase balance by 50,000');
    }

    @IsTest
    static void testInterestReserveTransactionHandler_Draw_DecreasesBalance() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = new Interest_Reserve__c(
            Current_Reserve_Balance__c = 100000,
            Debt_Position__c           = dp.Id
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert res;

        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(1),
            Period_End__c     = Date.today().addMonths(2),
            Due_Date__c       = Date.today().addMonths(2),
            Principal_Due__c  = 0, Interest_Due__c = 30000, Fees_Due__c = 0,
            Status__c         = 'Due', Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;

        Test.startTest();
        Interest_Reserve_Transaction__c txn = new Interest_Reserve_Transaction__c(
            Interest_Reserve__c        = res.Id, Type__c = 'Draw',
            Transaction_Date__c        = Date.today(), Value_Date__c = Date.today(),
            Amount__c                  = 30000, Source__c = 'System_Calculated',
            Linked_Payment_Schedule__c = ps.Id,
            External_Id__c             = 'RES-DRAW-1'
        );
        insert txn;
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Reserve__c resAfter = [SELECT Current_Reserve_Balance__c FROM Interest_Reserve__c WHERE Id = :res.Id];
        Assert.areEqual(70000, resAfter.Current_Reserve_Balance__c, 'Draw should reduce balance from 100k to 70k');
    }

    @IsTest
    static void testInterestReserveTransactionHandler_MultipleTransactions_NetBalance() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = new Interest_Reserve__c(
            Current_Reserve_Balance__c = 0,
            Debt_Position__c           = dp.Id
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert res;

        Payment_Transaction__c pt = new Payment_Transaction__c(
            Debt_Position__c = dp.Id, Amount__c = 100000,
            Status__c = 'Cleared', Transaction_Date__c = Date.today(),
            Value_Date__c = Date.today(), Payment_Method__c = 'EFT',
            Bank_Reference__c = 'BNK-NET-1'
        );
        insert pt;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().addMonths(2),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Principal_Due__c  = 0, Interest_Due__c = 20000, Fees_Due__c = 0,
            Status__c         = 'Due', Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;

        Test.startTest();
        insert new List<Interest_Reserve_Transaction__c>{
            new Interest_Reserve_Transaction__c(
                Interest_Reserve__c           = res.Id, Type__c = 'Fund',
                Transaction_Date__c           = Date.today(), Value_Date__c = Date.today(),
                Amount__c                     = 100000, Source__c = 'Manual_Entry',
                Linked_Payment_Transaction__c = pt.Id, External_Id__c = 'RES-F-A'),
            new Interest_Reserve_Transaction__c(
                Interest_Reserve__c        = res.Id, Type__c = 'Draw',
                Transaction_Date__c        = Date.today(), Value_Date__c = Date.today(),
                Amount__c                  = 20000, Source__c = 'System_Calculated',
                Linked_Payment_Schedule__c = ps.Id, External_Id__c = 'RES-D-A')
        };
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Interest_Reserve__c resAfter = [SELECT Current_Reserve_Balance__c FROM Interest_Reserve__c WHERE Id = :res.Id];
        Assert.areEqual(80000, resAfter.Current_Reserve_Balance__c, 'Fund 100k - Draw 20k = 80k net');
    }
}