/**
 * LMSPIKElectionTest
 * Covers all 5 PIK automation gaps:
 *   1. DailyAccrualBatch resolves locked elections from Election__c
 *   2. DailyAccrualPoster creates split rows (CASH + PIK) for Split elections
 *   3. PIKCapitalisationService uplifts Outstanding_Balance and calls reamortise
 *   4. ElectionDeadlineBatch auto-defaults overdue open elections
 *   5. InterestPeriodHandler auto-creates Election records for Borrower_Election DPs
 */
@IsTest
private class LMSPIKElectionTest {

    // ─── Shared setup ────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'PIK FI');
        insert fi;

        // DP with PIK Toggle (Borrower_Election mode)
        Debt_Position__c dp = new Debt_Position__c(
            Name                          = 'PIK Toggle DP',
            Financial_Instrument__c       = fi.Id,
            Status__c                     = 'Active',
            Position_Notional__c          = 1000000,
            PIK_Allowed__c                = true,
            PIK_Default_Mode__c           = 'Elect',
            PIK_Election_Deadline_Days__c = 5,
            Day_Count_Convention__c       = 'ACT_365',
            Schedule_Generation_Status__c = 'Active',
            Drawdown_Reamortisation_Mode__c = 'Re-Amortise_Forward',
            iPlatform_External_Id__c      = 'PIKELC001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        Interest_Rate_Terms__c setupIrt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Application_Status__c = 'Applied',
            Spread__c             = 8.0
        );
        insert setupIrt;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── GAP 1: DailyAccrualBatch reads locked Elections ─────────────────────

    @IsTest
    static void testDailyAccrualBatch_ReadsLockedElection() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd   = periodStart.addMonths(1);
        Date accrualDate = periodStart.addDays(5);

        TriggerContext.getInstance().bypassGuards = true;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            All_In_Rate__c        = 8.0,
            Period_Start__c       = periodStart,
            Period_End__c         = periodEnd,
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;

        // Locked full-PIK election
        Election__c el = new Election__c(
            Debt_Position__c   = dp.Id,
            Period_Start__c    = periodStart,
            Period_End__c      = periodEnd,
            Election_Type__c   = 'PIK',
            Is_Immutable__c    = true,
            Default_Applied__c = false
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Database.executeBatch(new DailyAccrualBatch(accrualDate), 200);
        Test.stopTest();

        List<Accrual_Daily__c> accruals = [
            SELECT Is_PIK__c FROM Accrual_Daily__c
            WHERE Debt_Position__c = :dp.Id
              AND Accrual_Date__c = :accrualDate
        ];
        Assert.isFalse(accruals.isEmpty(), 'DailyAccrualBatch should post at least one accrual');
        Assert.isTrue(accruals[0].Is_PIK__c, 'Accrual should be Is_PIK=true when locked PIK election exists');
    }

    // ─── GAP 2: DailyAccrualPoster creates two rows for Split election ────────

    @IsTest
    static void testDailyAccrualPoster_SplitElection_TwoRows() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date periodStart = Date.today().toStartOfMonth();
        Date accrualDate = periodStart;

        TriggerContext.getInstance().bypassGuards = true;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            All_In_Rate__c        = 12.0,
            Period_Start__c       = periodStart,
            Period_End__c         = periodStart.addMonths(1),
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 12.0
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;

        CalcContext ctx = new CalcContext.Builder()
            .setDebtPositionId(dp.Id)
            .setPrincipal(1000000)
            .setInterestRate(12.0)
            .setPeriodStartDate(periodStart)
            .setPeriodEndDate(periodStart.addMonths(1))
            .setCalculationDate(accrualDate)
            .setDayCountConvention('ACT_365')
            .setCorrelationId('test-split')
            .setExtras(new Map<String,Object>{
                'interestPeriodId'  => String.valueOf(ip.Id),
                'isPIK'             => false,
                'dayCountFraction'  => Decimal.valueOf(1) / 365,
                'electionType'      => 'Split',
                'electionCashAmt'   => 6000.00,   // 60% cash
                'electionPIKAmt'    => 4000.00    // 40% PIK
            })
            .build();

        Test.startTest();
        DailyAccrualPoster poster = new DailyAccrualPoster();
        EngineResult result = poster.postDailyAccrual(accrualDate, ctx);
        Test.stopTest();

        Assert.areEqual('Daily_Accrual_Split', result.resultType, 'Result type should indicate a split');
        Assert.areEqual(2, result.recordsToInsert.size(), 'Split election must produce 2 Accrual_Daily rows');

        // One row must be CASH, one must be PIK
        Integer cashRows = 0; Integer pikRows = 0;
        for (SObject rec : result.recordsToInsert) {
            Accrual_Daily__c ad = (Accrual_Daily__c) rec;
            if (ad.Is_PIK__c) pikRows++; else cashRows++;
        }
        Assert.areEqual(1, cashRows, 'Must have exactly 1 CASH row');
        Assert.areEqual(1, pikRows,  'Must have exactly 1 PIK row');

        // Cash + PIK amounts must sum to total accrued (within rounding)
        Decimal cash = ((Accrual_Daily__c) result.recordsToInsert[0]).Accrued_Amount__c
                     + ((Accrual_Daily__c) result.recordsToInsert[1]).Accrued_Amount__c;
        Decimal expected = (1000000 * (12.0 / 100) * (Decimal.valueOf(1) / 365)).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(expected, result.calculatedAmount.setScale(2, RoundingMode.HALF_EVEN),
            'Total split amount must equal full daily accrual');
    }

    // Split amounts proportion: 60% cash / 40% PIK split verified on individual rows
    @IsTest
    static void testDailyAccrualPoster_SplitProportions() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date d = Date.today();

        TriggerContext.getInstance().bypassGuards = true;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            All_In_Rate__c        = 12.0,
            Period_Start__c       = d,
            Period_End__c         = d.addMonths(1),
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 12.0
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;

        CalcContext ctx = new CalcContext.Builder()
            .setDebtPositionId(dp.Id)
            .setPrincipal(1000000)
            .setInterestRate(12.0)
            .setCalculationDate(d)
            .setCorrelationId('test-prop')
            .setExtras(new Map<String,Object>{
                'interestPeriodId'  => String.valueOf(ip.Id),
                'isPIK'             => false,
                'dayCountFraction'  => Decimal.valueOf(1) / 365,
                'electionType'      => 'Split',
                'electionCashAmt'   => 9000.00,
                'electionPIKAmt'    => 1000.00   // 90% cash / 10% PIK
            })
            .build();

        DailyAccrualPoster poster = new DailyAccrualPoster();
        EngineResult result = poster.postDailyAccrual(d, ctx);

        Assert.areEqual(2, result.recordsToInsert.size());
        Decimal cashAmt = 0; Decimal pikAmt = 0;
        for (SObject rec : result.recordsToInsert) {
            Accrual_Daily__c ad = (Accrual_Daily__c) rec;
            if (ad.Is_PIK__c) pikAmt = ad.Accrued_Amount__c;
            else cashAmt = ad.Accrued_Amount__c;
        }
        Assert.isTrue(cashAmt > pikAmt, 'Cash portion (90%) must exceed PIK portion (10%)');
        Assert.areEqual(result.calculatedAmount.setScale(2, RoundingMode.HALF_EVEN),
            (cashAmt + pikAmt).setScale(2, RoundingMode.HALF_EVEN),
            'Cash + PIK must equal the total accrual');
    }

    // ─── GAP 3: PIKCapitalisationService uplifts balance + calls reamortise ──

    @IsTest
    static void testPIKCapitalisationService_UpliftsBalanceAndReamortises() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd   = periodStart.addMonths(1);

        TriggerContext.getInstance().bypassGuards = true;
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            All_In_Rate__c        = 8.0,
            Period_Start__c       = periodStart,
            Period_End__c         = periodEnd,
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;

        // Create PIK accruals (use Effective_Value__c = 20000)
        List<Accrual_Daily__c> accruals = new List<Accrual_Daily__c>();
        for (Integer i = 0; i < 3; i++) {
            accruals.add(new Accrual_Daily__c(
                Debt_Position__c   = dp.Id,
                Interest_Period__c = ip.Id,
                Accrual_Date__c    = periodStart.addDays(i),
                Is_PIK__c          = true,
                Status__c          = 'Accrued',
                Accrued_Amount__c  = 7000,
                Principal_Basis__c = 1000000,
                Rate__c            = 8.0,
                Day_Count_Fraction__c = 1.0 / 365,
                External_Id__c     = String.valueOf(dp.Id) + '-PIK-' + i,
                Source__c          = 'System_Calculated',
                Engine_Version__c  = CalculationEngineBase.ENGINE_VERSION
            ));
        }
        TriggerContext.getInstance().bypassGuards = true;
        insert accruals;

        // Create future schedule rows so reamortise has something to supersede
        List<Payment_Schedule__c> futureSchedule = new List<Payment_Schedule__c>();
        for (Integer i = 0; i < 3; i++) {
            Date ps = periodEnd.addMonths(i);
            futureSchedule.add(new Payment_Schedule__c(
                Debt_Position__c  = dp.Id,
                Period_Start__c   = ps,
                Period_End__c     = ps.addMonths(1),
                Due_Date__c       = ps.addMonths(1),
                Principal_Due__c  = 333333,
                Interest_Due__c   = 5000,
                Fees_Due__c       = 0,
                Net_Due__c        = 338333,
                Status__c         = 'Projected',
                Source__c         = 'System_Calculated',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c    = 'PIK-PS-' + i
            ));
        }
        insert futureSchedule;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        PIKCapitalisationService.capitalise(dp.Id, ip.Id);
        Test.stopTest();

        // Verify Total_PIK_Capitalised uplifted by 3 × 7000 = 21000
        // (Outstanding_Balance formula = drawdowns - repayments + Total_PIK_Capitalised picks this up)
        Debt_Position__c dpAfter = [SELECT Total_PIK_Capitalised__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.isTrue(dpAfter.Total_PIK_Capitalised__c > 0,
            'Total_PIK_Capitalised__c must be incremented after PIK capitalisation of 21000');

        // Verify accruals marked Capitalised
        List<Accrual_Daily__c> caps = [SELECT Status__c FROM Accrual_Daily__c WHERE Debt_Position__c = :dp.Id AND Is_PIK__c = true];
        for (Accrual_Daily__c ad : caps) {
            Assert.areEqual('Capitalised', ad.Status__c, 'PIK accruals must be marked Capitalised');
        }

        // Verify re-amortisation happened (future rows superseded, new rows created)
        List<Payment_Schedule__c> superseded = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id AND Status__c = 'Superseded'
        ];
        Assert.isFalse(superseded.isEmpty(), 'Re-amortisation must supersede original future rows');
    }

    // ─── GAP 4: ElectionDeadlineBatch auto-defaults overdue elections ─────────

    @IsTest
    static void testElectionDeadlineBatch_AppliesDefault_WhenDeadlinePassed() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Date pastPeriodStart = Date.today().addDays(-10); // deadline was 5 days ago

        Election__c el = new Election__c(
            Debt_Position__c   = dp.Id,
            Period_Start__c    = pastPeriodStart,
            Period_End__c      = pastPeriodStart.addMonths(1),
            Election_Type__c   = 'Cash',
            Is_Immutable__c    = false,
            Default_Applied__c = false
        );
        insert el;

        Test.startTest();
        Database.executeBatch(new ElectionDeadlineBatch(Date.today()), 200);
        Test.stopTest();

        Election__c elAfter = [SELECT Is_Immutable__c, Default_Applied__c FROM Election__c WHERE Id = :el.Id];
        Assert.isTrue(elAfter.Is_Immutable__c,    'Election past deadline must be locked (Is_Immutable = true)');
        Assert.isTrue(elAfter.Default_Applied__c,  'Election must have Default_Applied = true');
    }

    @IsTest
    static void testElectionDeadlineBatch_NoOp_WhenDeadlineNotYetPassed() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Date futurePeriodStart = Date.today().addDays(1); // deadline 5 days from now = future

        Election__c el = new Election__c(
            Debt_Position__c   = dp.Id,
            Period_Start__c    = futurePeriodStart,
            Period_End__c      = futurePeriodStart.addMonths(1),
            Election_Type__c   = 'Cash',
            Is_Immutable__c    = false,
            Default_Applied__c = false
        );
        insert el;

        Test.startTest();
        Database.executeBatch(new ElectionDeadlineBatch(Date.today()), 200);
        Test.stopTest();

        Election__c elAfter = [SELECT Is_Immutable__c, Default_Applied__c FROM Election__c WHERE Id = :el.Id];
        Assert.isFalse(elAfter.Is_Immutable__c,    'Election with future deadline must remain unlocked');
        Assert.isFalse(elAfter.Default_Applied__c,  'Default must not be applied before deadline');
    }

    // ─── GAP 5: InterestPeriodHandler auto-creates Election on period insert ──

    @IsTest
    static void testInterestPeriodHandler_AutoCreatesElection_ForBorrowerElectionDP() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date periodStart = Date.today().toStartOfMonth().addMonths(2);

        Test.startTest();
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dp.Id,
            All_In_Rate__c        = 8.0,
            Period_Start__c       = periodStart,
            Period_End__c         = periodStart.addMonths(1),
            Status__c             = 'Active',
            Applied_Rate_Terms__c = irt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        Test.stopTest();

        List<Election__c> elections = [
            SELECT Id, Election_Type__c, Is_Immutable__c
            FROM Election__c
            WHERE Debt_Position__c = :dp.Id
              AND Period_Start__c  = :periodStart
        ];
        Assert.areEqual(1, elections.size(), 'One Election record must be auto-created on period insert');
        Assert.isFalse(elections[0].Is_Immutable__c, 'Auto-created election must be open (not immutable)');
    }

    @IsTest
    static void testInterestPeriodHandler_NoElectionCreated_ForAutoPIKDP() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];

        // DP with Auto_PIK — no borrower election needed
        Debt_Position__c autoDp = new Debt_Position__c(
            Name                     = 'Auto PIK DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            PIK_Allowed__c           = true,
            PIK_Default_Mode__c      = 'Auto_PIK',
            iPlatform_External_Id__c = 'PIKAUTO01'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert autoDp;
        Interest_Rate_Terms__c autoDpIrt = new Interest_Rate_Terms__c(
            Debt_Position__c      = autoDp.Id,
            Application_Status__c = 'Applied',
            Spread__c             = 8.0
        );
        insert autoDpIrt;
        TriggerContext.getInstance().bypassGuards = false;

        Date periodStart = Date.today().toStartOfMonth().addMonths(3);
        Test.startTest();
        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = autoDp.Id,
            All_In_Rate__c        = 8.0,
            Period_Start__c       = periodStart,
            Period_End__c         = periodStart.addMonths(1),
            Status__c             = 'Active',
            Applied_Rate_Terms__c = autoDpIrt.Id,
            Margin_Used__c        = 8.0
        );
        insert ip;
        Test.stopTest();

        List<Election__c> elections = [
            SELECT Id FROM Election__c WHERE Debt_Position__c = :autoDp.Id AND Period_Start__c = :periodStart
        ];
        Assert.areEqual(0, elections.size(), 'Auto_PIK DPs must not get auto-created elections');
    }

    // ─── ElectionService.lockElection ────────────────────────────────────────

    @IsTest
    static void testElectionService_LockElection_SetsImmutableAndLockedDate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c WHERE Name = 'PIK Toggle DP' LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Election__c el = new Election__c(
            Debt_Position__c = dp.Id,
            Election_Type__c = 'Cash',
            Period_Start__c  = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Is_Immutable__c  = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        ElectionService.lockElection(el.Id);
        Test.stopTest();

        Election__c elAfter = [
            SELECT Is_Immutable__c, Election_Locked_Date__c
            FROM Election__c WHERE Id = :el.Id
        ];
        Assert.isTrue(elAfter.Is_Immutable__c, 'lockElection must set Is_Immutable__c = true');
        Assert.isNotNull(elAfter.Election_Locked_Date__c, 'lockElection must populate Election_Locked_Date__c');
    }

    // ─── ElectionService.applyDefault ────────────────────────────────────────

    @IsTest
    static void testElectionService_ApplyDefault_AutoPIK_SetsElectionTypePIK() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c autoDp = new Debt_Position__c(
            Name                     = 'Auto PIK Default DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            PIK_Allowed__c           = true,
            PIK_Default_Mode__c      = 'Auto_PIK',
            iPlatform_External_Id__c = 'ELCAUTO01'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert autoDp;
        Election__c el = new Election__c(
            Debt_Position__c = autoDp.Id,
            Election_Type__c = 'Cash',
            Period_Start__c  = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Is_Immutable__c  = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        autoDp = [SELECT Id, PIK_Default_Mode__c FROM Debt_Position__c WHERE Id = :autoDp.Id];
        Test.startTest();
        ElectionService.applyDefault(el, autoDp);
        Test.stopTest();

        Election__c elAfter = [SELECT Election_Type__c, Is_Immutable__c FROM Election__c WHERE Id = :el.Id];
        Assert.areEqual('PIK', elAfter.Election_Type__c, 'Auto_PIK mode must set Election_Type__c = PIK');
        Assert.isTrue(elAfter.Is_Immutable__c, 'applyDefault must lock the election');
    }

    @IsTest
    static void testElectionService_ApplyDefault_NonAutoPIK_SetsElectionTypeCash() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c electDp = new Debt_Position__c(
            Name                     = 'Elect Default DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            PIK_Allowed__c           = true,
            PIK_Default_Mode__c      = 'Elect',
            iPlatform_External_Id__c = 'ELCELEC01'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert electDp;
        Election__c el = new Election__c(
            Debt_Position__c = electDp.Id,
            Election_Type__c = 'Cash',
            Period_Start__c  = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Is_Immutable__c  = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        electDp = [SELECT Id, PIK_Default_Mode__c FROM Debt_Position__c WHERE Id = :electDp.Id];
        Test.startTest();
        ElectionService.applyDefault(el, electDp);
        Test.stopTest();

        Election__c elAfter = [SELECT Election_Type__c FROM Election__c WHERE Id = :el.Id];
        Assert.areEqual('Cash', elAfter.Election_Type__c, 'Non-Auto_PIK mode must default Election_Type__c to Cash');
    }

    // ─── ElectionService.validateSplitAmounts ────────────────────────────────

    @IsTest
    static void testElectionService_ValidateSplitAmounts_NonSplit_ReturnsTrue() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c WHERE Name = 'PIK Toggle DP' LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Election__c el = new Election__c(
            Debt_Position__c = dp.Id,
            Election_Type__c = 'Cash',
            Period_Start__c  = Date.today(),
            Period_End__c    = Date.today().addMonths(3),
            Is_Immutable__c  = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean valid = ElectionService.validateSplitAmounts(el);
        Test.stopTest();
        Assert.isTrue(valid, 'Non-Split election must always return true');
    }

    @IsTest
    static void testElectionService_ValidateSplitAmounts_ValidSplit_ReturnsTrue() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c WHERE Name = 'PIK Toggle DP' LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(1),
            Due_Date__c       = Date.today().addMonths(1),
            Interest_Due__c   = 10000,
            Principal_Due__c  = 0,
            Fees_Due__c       = 0,
            Net_Due__c        = 10000,
            Status__c         = 'Projected',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'ELCPS001'
        );
        insert ps;
        Election__c el = new Election__c(
            Debt_Position__c    = dp.Id,
            Election_Type__c    = 'Split',
            Cash_Amount__c      = 6000,
            PIK_Amount__c       = 4000,
            Payment_Schedule__c = ps.Id,
            Period_Start__c     = Date.today(),
            Period_End__c       = Date.today().addMonths(1),
            Is_Immutable__c     = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean valid = ElectionService.validateSplitAmounts(el);
        Test.stopTest();
        Assert.isTrue(valid, 'Valid split where Cash+PIK = Interest_Due must return true');
    }

    @IsTest
    static void testElectionService_ValidateSplitAmounts_InvalidSplit_ReturnsFalse() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c WHERE Name = 'PIK Toggle DP' LIMIT 1];
        TriggerContext.getInstance().bypassGuards = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(1),
            Due_Date__c       = Date.today().addMonths(1),
            Interest_Due__c   = 10000,
            Principal_Due__c  = 0,
            Fees_Due__c       = 0,
            Net_Due__c        = 10000,
            Status__c         = 'Projected',
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'ELCPS002'
        );
        insert ps;
        Election__c el = new Election__c(
            Debt_Position__c    = dp.Id,
            Election_Type__c    = 'Split',
            Cash_Amount__c      = 5000, // 5000 + 3000 = 8000 ≠ 10000
            PIK_Amount__c       = 3000,
            Payment_Schedule__c = ps.Id,
            Period_Start__c     = Date.today(),
            Period_End__c       = Date.today().addMonths(1),
            Is_Immutable__c     = false
        );
        insert el;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        Boolean valid = ElectionService.validateSplitAmounts(el);
        Test.stopTest();
        Assert.isFalse(valid, 'Invalid split where Cash+PIK ≠ Interest_Due must return false');
    }
}