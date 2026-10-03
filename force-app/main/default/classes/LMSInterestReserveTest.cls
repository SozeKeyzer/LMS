/**
 * LMSInterestReserveTest
 * Covers: InterestReserveService (autoApplyReserve, fundReserve @InvocableMethod)
 */
@IsTest
private class LMSInterestReserveTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Reserve FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                             = 'Reserve DP',
            Financial_Instrument__c          = fi.Id,
            Status__c                        = 'Active',
            Interest_Reserve_Default_Mode__c = 'Auto',
            iPlatform_External_Id__c         = 'RESRV-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        // Override lookup field to use Source_Reference__c so query resolves in test context
        // InterestReserveService.IR_FI_LOOKUP_FIELD is @TestVisible but the real query
        // uses Financial_Instrument__c. Insert a reserve with Source_Reference__c = fi.Id
        // and override IR_FI_LOOKUP_FIELD to 'Source_Reference__c' for this test.
        Interest_Reserve__c res = new Interest_Reserve__c(
            Debt_Position__c           = dp.Id,
            Current_Reserve_Balance__c = 200000,
            Source_Reference__c        = fi.Id,
            Source__c                  = 'Manual_Entry'
        );
        insert res;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── InterestReserveService.autoApplyReserve ─────────────────────────────

    @IsTest
    static void testAutoApplyReserve_WithSufficientBalance_CreatesDrawTransaction() {
        Debt_Position__c dp = [SELECT Id, Financial_Instrument__c FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = [SELECT Id, Current_Reserve_Balance__c FROM Interest_Reserve__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().toStartOfMonth(),
            Period_End__c     = Date.today().toStartOfMonth().addMonths(1),
            Due_Date__c       = Date.today().toStartOfMonth().addMonths(1),
            Principal_Due__c  = 0,
            Interest_Due__c   = 50000,
            Fees_Due__c       = 0,
            Net_Due__c        = 50000,
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        // Override lookup field so the dynamic SOQL hits Source_Reference__c = fiId
        InterestReserveService.IR_FI_LOOKUP_FIELD = 'Source_Reference__c';

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        InterestReserveService.autoApplyReserve(ps, dp);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        List<Interest_Reserve_Transaction__c> draws = [
            SELECT Id, Amount__c, Type__c FROM Interest_Reserve_Transaction__c
            WHERE Linked_Payment_Schedule__c = :ps.Id AND Type__c = 'Draw'
        ];
        Assert.isFalse(draws.isEmpty(), 'autoApplyReserve must create a Draw transaction');
        Assert.areEqual(50000, draws[0].Amount__c, 'Draw must equal Net_Due');
    }

    @IsTest
    static void testAutoApplyReserve_InsufficientBalance_NoTransaction() {
        Debt_Position__c dp = [SELECT Id, Financial_Instrument__c FROM Debt_Position__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().toStartOfMonth().addMonths(2),
            Period_End__c     = Date.today().toStartOfMonth().addMonths(3),
            Due_Date__c       = Date.today().toStartOfMonth().addMonths(3),
            Principal_Due__c  = 0,
            Interest_Due__c   = 500000,
            Fees_Due__c       = 0,
            Net_Due__c        = 500000, // more than the 200k balance
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        InterestReserveService.IR_FI_LOOKUP_FIELD = 'Source_Reference__c';

        TriggerContext.getInstance().bypassGuards = true;
        InterestReserveService.autoApplyReserve(ps, dp);
        TriggerContext.getInstance().bypassGuards = false;

        List<Interest_Reserve_Transaction__c> draws = [
            SELECT Id FROM Interest_Reserve_Transaction__c
            WHERE Linked_Payment_Schedule__c = :ps.Id AND Type__c = 'Draw'
        ];
        Assert.isTrue(draws.isEmpty(), 'Insufficient balance must produce no Draw transaction');
    }

    @IsTest
    static void testAutoApplyReserve_NoFinancialInstrument_NoOp() {
        Debt_Position__c dpNoFi = new Debt_Position__c(
            Name                     = 'No FI DP',
            Status__c                = 'Active',
            iPlatform_External_Id__c = 'RESRV-002'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dpNoFi;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dpNoFi.Id,
            Period_Start__c   = Date.today().toStartOfMonth().addMonths(4),
            Period_End__c     = Date.today().toStartOfMonth().addMonths(5),
            Due_Date__c       = Date.today().toStartOfMonth().addMonths(5),
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Net_Due__c        = 10000,
            Status__c         = 'Due',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;
        TriggerContext.getInstance().bypassGuards = false;

        Boolean threw = false;
        try {
            TriggerContext.getInstance().bypassGuards = true;
            InterestReserveService.autoApplyReserve(ps, dpNoFi);
            TriggerContext.getInstance().bypassGuards = false;
        } catch (Exception e) { threw = true; }

        Assert.isFalse(threw, 'Missing FI must result in silent no-op, not exception');
    }

    // ─── InterestReserveService.fundReserve (@InvocableMethod) ───────────────

    @IsTest
    static void testFundReserve_InvocableMethod_InsertsFundTransaction() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = [SELECT Id, Current_Reserve_Balance__c FROM Interest_Reserve__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Transaction__c pt = new Payment_Transaction__c(
            Debt_Position__c = dp.Id, Amount__c = 75000,
            Status__c = 'Cleared', Transaction_Date__c = Date.today(),
            Value_Date__c = Date.today(), Payment_Method__c = 'EFT',
            Bank_Reference__c = 'BNK-FUND-INV-1'
        );
        insert pt;
        TriggerContext.getInstance().bypassGuards = false;

        InterestReserveService.FundReserveRequest req = new InterestReserveService.FundReserveRequest();
        req.reserveId            = res.Id;
        req.transactionType      = 'Fund';
        req.transactionDate      = Date.today();
        req.valueDate            = Date.today();
        req.amount               = 75000;
        req.paymentTransactionId = pt.Id;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        InterestReserveService.fundReserve(new List<InterestReserveService.FundReserveRequest>{ req });
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        List<Interest_Reserve_Transaction__c> funds = [
            SELECT Id, Amount__c, Type__c
            FROM Interest_Reserve_Transaction__c
            WHERE Type__c = 'Fund'
        ];
        Assert.isFalse(funds.isEmpty(), 'fundReserve must create a Fund transaction');
        Assert.areEqual(75000, funds[0].Amount__c);
    }

    @IsTest
    static void testFundReserve_MultipleRequests_InsertsAll() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = [SELECT Id FROM Interest_Reserve__c LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        List<Payment_Transaction__c> pts = new List<Payment_Transaction__c>();
        for (Integer i = 0; i < 3; i++) {
            pts.add(new Payment_Transaction__c(
                Debt_Position__c = dp.Id, Amount__c = 10000 * (i + 1),
                Status__c = 'Cleared', Transaction_Date__c = Date.today().addDays(i),
                Value_Date__c = Date.today().addDays(i), Payment_Method__c = 'EFT',
                Bank_Reference__c = 'BNK-MULTI-' + i
            ));
        }
        insert pts;
        TriggerContext.getInstance().bypassGuards = false;

        List<InterestReserveService.FundReserveRequest> reqs = new List<InterestReserveService.FundReserveRequest>();
        for (Integer i = 0; i < 3; i++) {
            InterestReserveService.FundReserveRequest req = new InterestReserveService.FundReserveRequest();
            req.reserveId            = res.Id;
            req.transactionType      = 'Fund';
            req.transactionDate      = Date.today().addDays(i);
            req.amount               = 10000 * (i + 1);
            req.paymentTransactionId = pts[i].Id;
            reqs.add(req);
        }

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        InterestReserveService.fundReserve(reqs);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Interest_Reserve_Transaction__c WHERE Type__c = 'Fund'];
        Assert.areEqual(3, cnt, 'fundReserve must insert one transaction per request');
    }

    // ─── Direct transaction inserts (handler coverage) ────────────────────────

    @IsTest
    static void testDirectFundInsert_IncreasesBalance() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = [SELECT Id, Current_Reserve_Balance__c FROM Interest_Reserve__c LIMIT 1];
        Decimal before = res.Current_Reserve_Balance__c;

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Transaction__c pt = new Payment_Transaction__c(
            Debt_Position__c = dp.Id, Amount__c = 50000,
            Status__c = 'Cleared', Transaction_Date__c = Date.today(),
            Value_Date__c = Date.today(), Payment_Method__c = 'EFT',
            Bank_Reference__c = 'BNK-DIR-FUND-1'
        );
        insert pt;
        Interest_Reserve_Transaction__c txn = new Interest_Reserve_Transaction__c(
            Interest_Reserve__c           = res.Id,
            Type__c                       = 'Fund',
            Transaction_Date__c           = Date.today(),
            Value_Date__c                 = Date.today(),
            Amount__c                     = 50000,
            Linked_Payment_Transaction__c = pt.Id,
            Source__c                     = 'Manual_Entry',
            External_Id__c                = 'TEST-FUND-' + Date.today().format()
        );
        insert txn;
        TriggerContext.getInstance().bypassGuards = false;

        Interest_Reserve__c resAfter = [SELECT Current_Reserve_Balance__c FROM Interest_Reserve__c WHERE Id = :res.Id];
        Assert.areEqual(before + 50000, resAfter.Current_Reserve_Balance__c,
            'Fund transaction must increase Current_Reserve_Balance__c');
    }

    @IsTest
    static void testDirectDrawInsert_DecreasesBalance() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Reserve__c res = [SELECT Id, Current_Reserve_Balance__c FROM Interest_Reserve__c LIMIT 1];
        Decimal before = res.Current_Reserve_Balance__c;

        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today().toStartOfMonth(),
            Period_End__c     = Date.today().toStartOfMonth().addMonths(1),
            Due_Date__c       = Date.today().toStartOfMonth().addMonths(1),
            Principal_Due__c  = 0, Interest_Due__c = 30000, Fees_Due__c = 0,
            Status__c         = 'Due', Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION
        );
        insert ps;
        Interest_Reserve_Transaction__c txn = new Interest_Reserve_Transaction__c(
            Interest_Reserve__c        = res.Id,
            Type__c                    = 'Draw',
            Transaction_Date__c        = Date.today(),
            Value_Date__c              = Date.today(),
            Amount__c                  = 30000,
            Linked_Payment_Schedule__c = ps.Id,
            Source__c                  = 'System_Calculated',
            External_Id__c             = 'TEST-DRAW-' + Date.today().format()
        );
        insert txn;
        TriggerContext.getInstance().bypassGuards = false;

        Interest_Reserve__c resAfter = [SELECT Current_Reserve_Balance__c FROM Interest_Reserve__c WHERE Id = :res.Id];
        Assert.areEqual(before - 30000, resAfter.Current_Reserve_Balance__c,
            'Draw transaction must decrease Current_Reserve_Balance__c');
    }
}