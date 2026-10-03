/**
 * LMSInterestPeriodServiceTest
 * Covers: InterestPeriodService (createActivePeriod, createPendingPeriod, lockPeriod, closePeriod),
 *         PaymentScheduleRateFinaliser (finaliseForFixings — rate computed and written)
 * Verifies VR.IP.05 overlap guard, floor/ceiling enforcement, and rate finalisation numerics.
 */
@IsTest
private class LMSInterestPeriodServiceTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'IP FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'IP DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Day_Count_Convention__c  = 'ACT_365',
            iPlatform_External_Id__c = 'IPRDS-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Application_Status__c = 'Applied',
            Spread__c             = 8.0
        );
        insert irt;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── createActivePeriod ───────────────────────────────────────────────────

    @IsTest
    static void testCreateActivePeriod_StatusIsActive() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth();
        Date periodEnd = start.addMonths(3);

        Test.startTest();
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 8.5, null, null, 'test-corr'
        );
        Test.stopTest();

        Assert.areEqual('Active', ip.Status__c, 'Fixed-rate period must be Active immediately');
        Assert.areEqual(8.5, ip.All_In_Rate__c, 'All_In_Rate must match contractual rate');
    }

    @IsTest
    static void testCreateActivePeriod_FloorEnforced() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(1);
        Date periodEnd = start.addMonths(3);
        // Rate 2% < floor 4% → all-in should be floored at 4%
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 2.0, 4.0, 10.0, 'floor-test'
        );
        Assert.areEqual(4.0, ip.All_In_Rate__c, 'Rate below floor must be raised to floor (4%)');
    }

    @IsTest
    static void testCreateActivePeriod_CeilingEnforced() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(2);
        Date periodEnd = start.addMonths(3);
        // Rate 15% > ceiling 12% → all-in should be capped at 12%
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 15.0, 2.0, 12.0, 'ceiling-test'
        );
        Assert.areEqual(12.0, ip.All_In_Rate__c, 'Rate above ceiling must be capped at ceiling (12%)');
    }

    @IsTest
    static void testCreateActivePeriod_OverlapThrows() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(4);
        Date periodEnd = start.addMonths(3);
        InterestPeriodService.createActivePeriod(dp.Id, irt.Id, start, periodEnd, 8.0, null, null, 'ip-1');

        // Overlapping period
        Boolean threw = false;
        try {
            InterestPeriodService.createActivePeriod(dp.Id, irt.Id, start.addMonths(1), periodEnd.addMonths(1), 8.0, null, null, 'ip-2');
        } catch (InterestPeriodService.InterestPeriodException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'VR.IP.05: overlapping Active period must throw InterestPeriodException');
    }

    // ─── createPendingPeriod ──────────────────────────────────────────────────

    @IsTest
    static void testCreatePendingPeriod_StatusIsPending() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(7);
        Date periodEnd = start.addMonths(3);

        Test.startTest();
        Interest_Period__c ip = InterestPeriodService.createPendingPeriod(
            dp.Id, irt.Id, start, periodEnd, 'BBSW 3M', Date.today(), 2.5, 'pend-corr'
        );
        Test.stopTest();

        Assert.areEqual('Pending', ip.Status__c, 'Floating-rate period must be Pending until fixing');
        Assert.areEqual(0, ip.All_In_Rate__c, 'All_In_Rate must be 0 before fixing');
    }

    // ─── lockPeriod ───────────────────────────────────────────────────────────

    @IsTest
    static void testLockPeriod_SetsAllInRate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(10);
        Date periodEnd = start.addMonths(3);
        Interest_Period__c ip = InterestPeriodService.createPendingPeriod(
            dp.Id, irt.Id, start, periodEnd, 'BBSW 3M', Date.today(), 2.0, 'lock-test'
        );

        Test.startTest();
        InterestPeriodService.lockPeriod(ip.Id, 3.5); // index 3.5% + margin 2.0% = 5.5%
        Test.stopTest();

        Interest_Period__c ipAfter = [SELECT All_In_Rate__c, Status__c FROM Interest_Period__c WHERE Id = :ip.Id];
        Assert.areEqual('Active', ipAfter.Status__c, 'Locked period must become Active');
        Assert.areEqual(5.5, ipAfter.All_In_Rate__c, 'All-in = 3.5 index + 2.0 margin = 5.5%');
    }

    @IsTest
    static void testLockPeriod_NonPending_NoOp() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(13);
        Date periodEnd = start.addMonths(3);
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 8.0, null, null, 'noop-lock'
        );
        Decimal originalRate = ip.All_In_Rate__c;
        // Locking an Active period → no-op
        InterestPeriodService.lockPeriod(ip.Id, 9.0);
        Interest_Period__c ipAfter = [SELECT All_In_Rate__c FROM Interest_Period__c WHERE Id = :ip.Id];
        Assert.areEqual(originalRate, ipAfter.All_In_Rate__c, 'Locking Active period must be a no-op');
    }

    // ─── closePeriod ──────────────────────────────────────────────────────────

    @IsTest
    static void testClosePeriod_StatusBecomeClosed() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(16);
        Date periodEnd = start.addMonths(3);
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 8.0, null, null, 'close-test'
        );

        Test.startTest();
        InterestPeriodService.closePeriod(ip.Id);
        Test.stopTest();

        Interest_Period__c ipAfter = [SELECT Status__c FROM Interest_Period__c WHERE Id = :ip.Id];
        Assert.areEqual('Closed', ipAfter.Status__c, 'closePeriod must set Status to Closed');
    }

    @IsTest
    static void testClosePeriod_CrystallisesAccruals() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date start = Date.today().toStartOfMonth().addMonths(19);
        Date periodEnd = start.addMonths(3);
        Interest_Period__c ip = InterestPeriodService.createActivePeriod(
            dp.Id, irt.Id, start, periodEnd, 8.0, null, null, 'cryst-test'
        );

        // Insert mutable accrual
        TriggerContext.getInstance().bypassGuards = true;
        Accrual_Daily__c ad = new Accrual_Daily__c(
            Debt_Position__c = dp.Id, Interest_Period__c = ip.Id,
            Accrual_Date__c  = start, Accrued_Amount__c = 500,
            Is_PIK__c = false, Status__c = 'Accrued',
            Principal_Basis__c = 1000000, Rate__c = 8.0,
            Day_Count_Fraction__c = 0.002739, Source__c = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c = String.valueOf(dp.Id) + '-cryst-' + start.format()
        );
        insert ad;
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        InterestPeriodService.closePeriod(ip.Id);
        Test.stopTest();

        Accrual_Daily__c adAfter = [SELECT Is_Immutable__c FROM Accrual_Daily__c WHERE Id = :ad.Id];
        Assert.isTrue(adAfter.Is_Immutable__c, 'closePeriod must crystallise accruals (Is_Immutable=true)');
    }

    // ─── PaymentScheduleRateFinaliser ────────────────────────────────────────

    @IsTest
    static void testRateFinaliser_SetsRateFinalisedAndRecomputesInterest() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id LIMIT 1];
        Date periodStart = Date.today().toStartOfMonth().addMonths(22);
        Date periodEnd   = periodStart.addMonths(3);

        // Create a Pending floating interest period
        Interest_Period__c ip = InterestPeriodService.createPendingPeriod(
            dp.Id, irt.Id, periodStart, periodEnd, 'BBSW 3M', Date.today(), 2.0, 'fin-test'
        );

        TriggerContext.getInstance().bypassGuards = true;
        // Create schedule with Projected_Rate status
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Debt_Position__c           = dp.Id,
            Period_Start__c            = periodStart, Period_End__c = periodEnd,
            Due_Date__c                = periodEnd,
            Principal_Due__c           = 1000000, Interest_Due__c = 0, Fees_Due__c = 0,
            Principal_Basis_Used__c    = 1000000,
            Day_Count_Convention_Used__c = 'ACT_365',
            Rate_Finalisation_Status__c = 'Projected_Rate',
            Status__c                  = 'Projected',
            Source__c                  = 'System_Calculated',
            Engine_Version__c          = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c             = 'PS-RATE-FIN-001'
        );
        insert ps;

        Rate_Index__c ri = new Rate_Index__c(Name = 'BBSW 3M');
        insert ri;
        TriggerContext.getInstance().bypassGuards = false;

        Rate_Index_Fixing__c fixing = new Rate_Index_Fixing__c(
            Rate_Index__c   = ri.Id, Fixing_Date__c = Date.today(),
            Rate__c         = 3.5,
            External_Id__c  = String.valueOf(ri.Id) + '-fin-' + Date.today().format()
        );
        insert fixing;

        Test.startTest();
        // finaliseForFixings locks the pending period internally and then finalises PS rows
        PaymentScheduleRateFinaliser.finaliseForFixings(new List<Rate_Index_Fixing__c>{ fixing });
        Test.stopTest();

        Payment_Schedule__c psAfter = [
            SELECT Rate_Finalisation_Status__c, Interest_Due__c, All_In_Rate_Used__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Assert.areEqual('Rate_Finalised', psAfter.Rate_Finalisation_Status__c,
            'finaliseForFixings must transition Projected_Rate → Rate_Finalised');
        Assert.isTrue(psAfter.Interest_Due__c > 0,
            'Interest_Due must be computed from principal × rate × dcf');
    }
}