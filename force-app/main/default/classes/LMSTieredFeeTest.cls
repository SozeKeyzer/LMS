/**
 * LMSTieredFeeTest
 * Covers TieredFeeResolver (band selection, computeBasisValue) and
 * FeeCapitalisationService (pending creation, notional uplift on activation).
 * Spec v3 Part 6.9, Part 6.10.
 */
@IsTest
private class LMSTieredFeeTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'TieredFee FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name = 'TieredFee DP',
            Financial_Instrument__c = fi.Id,
            Status__c = 'Active',
            Position_Notional__c = 1000000,
            iPlatform_External_Id__c = 'TIERD-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ── TieredFeeResolver ─────────────────────────────────────────────────────

    // Position_Notional = 1M, no drawdowns → Undrawn = 1M; falls in Tier 3 (800k+)
    @IsTest
    static void testResolveTier_MatchesMidTier() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Fee_Structures__c fs = new Fee_Structures__c(Debt_Position__c = dp.Id);
        insert fs;

        Fee_Tier__c t1 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 1,
            Threshold_Lower__c = 0,      Threshold_Upper__c = 400000, Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 0.5);
        Fee_Tier__c t2 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 2,
            Threshold_Lower__c = 400000, Threshold_Upper__c = 800000, Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 0.75);
        Fee_Tier__c t3 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 3,
            Threshold_Lower__c = 800000, Threshold_Upper__c = null,   Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 1.0);
        insert new List<Fee_Tier__c>{ t1, t2, t3 };

        // Re-query to get the Id back on fs (needed by resolveTier)
        Fee_Structures__c fsQ = [SELECT Id, Debt_Position__c FROM Fee_Structures__c WHERE Id = :fs.Id];

        Test.startTest();
        Fee_Tier__c matched = TieredFeeResolver.resolveTier(fsQ, Date.today());
        Test.stopTest();

        Assert.isNotNull(matched, 'Should find a tier for 1M undrawn amount');
        Assert.areEqual(t3.Id, matched.Id, 'Undrawn 1M should match tier 3 (800k+ band)');
        Assert.areEqual(1.0, matched.Applicable_Rate__c, 'Tier 3 rate = 1.0%');
    }

    // Open-ended upper tier: Undrawn = 1M; Tier2 has no upper bound → matches
    @IsTest
    static void testResolveTier_MatchesUpperOpenTier() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Fee_Structures__c fs = new Fee_Structures__c(Debt_Position__c = dp.Id);
        insert fs;
        Fee_Tier__c t1 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 1,
            Threshold_Lower__c = 0,      Threshold_Upper__c = 500000, Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 0.5);
        Fee_Tier__c t2 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 2,
            Threshold_Lower__c = 500000, Threshold_Upper__c = null,   Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 1.0);
        insert new List<Fee_Tier__c>{ t1, t2 };

        Fee_Structures__c fsQ = [SELECT Id, Debt_Position__c FROM Fee_Structures__c WHERE Id = :fs.Id];
        Fee_Tier__c matched = TieredFeeResolver.resolveTier(fsQ, Date.today());
        Assert.areEqual(t2.Id, matched.Id, '1M undrawn should match tier with no upper bound');
    }

    // No tiers → returns null (flat fee structure)
    @IsTest
    static void testResolveTier_NoTiers_ReturnsNull() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(Debt_Position__c = dp.Id);
        insert fs;

        Fee_Structures__c fsQ = [SELECT Id, Debt_Position__c FROM Fee_Structures__c WHERE Id = :fs.Id];
        Fee_Tier__c result = TieredFeeResolver.resolveTier(fsQ, Date.today());
        Assert.isNull(result, 'No tiers = flat fee; should return null');
    }

    // No matching tier → TieredFeeException thrown
    // Undrawn = 1M (Position_Notional=1M, no drawdowns); tier only covers 0–500k → gap above 500k
    @IsTest
    static void testResolveTier_NoMatch_ThrowsException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(Debt_Position__c = dp.Id);
        insert fs;
        Fee_Tier__c t1 = new Fee_Tier__c(Fee_Structure__c = fs.Id, Tier_Order__c = 1,
            Threshold_Lower__c = 0, Threshold_Upper__c = 500000, Threshold_Basis__c = 'Undrawn_Amount', Applicable_Rate__c = 0.5);
        insert t1;

        Fee_Structures__c fsQ = [SELECT Id, Debt_Position__c FROM Fee_Structures__c WHERE Id = :fs.Id];
        Boolean threw = false;
        try {
            TieredFeeResolver.resolveTier(fsQ, Date.today());
        } catch (TieredFeeResolver.TieredFeeException ex) {
            threw = true;
            Assert.isTrue(ex.getMessage().contains('No tier found'), 'Exception message should describe the gap');
        }
        Assert.isTrue(threw, 'Should throw TieredFeeException when no tier covers the basis value');
    }

    // computeBasisValue: Utilisation_Percent = Outstanding_Balance / Position_Notional
    // Outstanding_Balance is a formula (Total_Drawdown - Total_Repayment); with no drawdowns = 0
    @IsTest
    static void testComputeBasisValue_UtilisationPercent() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Decimal util = TieredFeeResolver.computeBasisValue(dp.Id, 'Utilisation_Percent', Date.today());
        Assert.areEqual(0, util, '0 drawdowns / 1M notional = 0 utilisation');
    }

    // Unknown basis throws TieredFeeException
    @IsTest
    static void testComputeBasisValue_UnknownBasis_Throws() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Boolean threw = false;
        try {
            TieredFeeResolver.computeBasisValue(dp.Id, 'Unknown_Basis', Date.today());
        } catch (TieredFeeResolver.TieredFeeException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    // ── FeeCapitalisationService ───────────────────────────────────────────────

    // capitaliseAtDueDate creates Pending FCE for Capitalised treatment
    @IsTest
    static void testCapitaliseAtDueDate_CreatesPendingFCE() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c  = dp.Id,
            Fee_Treatment__c  = 'Capitalised'
        );
        insert fs;

        Test.startTest();
        Fee_Capitalisation_Event__c fce = FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        Test.stopTest();

        Assert.isNotNull(fce, 'Should create FCE');
        Assert.areEqual('Pending', fce.Status__c, 'FCE should start as Pending');
        Assert.areEqual(dp.Id, fce.Debt_Position__c);
    }

    // capitaliseAtDueDate returns null for Cash treatment
    @IsTest
    static void testCapitaliseAtDueDate_CashTreatment_ReturnsNull() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c = dp.Id,
            Fee_Treatment__c = 'Cash'
        );
        insert fs;

        Test.startTest();
        Fee_Capitalisation_Event__c fce = FeeCapitalisationService.capitaliseAtDueDate(fs.Id, Date.today());
        Test.stopTest();

        Assert.isNull(fce, 'Cash treatment should return null (no capitalisation)');
    }

    // activateCapitalisation uplifts Position_Notional
    @IsTest
    static void testActivateCapitalisation_UpliftsNotional() {
        Debt_Position__c dp = [SELECT Id, Position_Notional__c FROM Debt_Position__c LIMIT 1];
        Decimal originalNotional = dp.Position_Notional__c; // 1,000,000

        // Insert active Amortisation_Rules so createSegmentFromCurrentActive doesn't blow up
        Amortisation_Rules__c ar = new Amortisation_Rules__c(
            Debt_Position__c = dp.Id
        );
        insert ar;

        // Create FCE manually (simulating approved state from approval process)
        Fee_Capitalisation_Event__c fce = new Fee_Capitalisation_Event__c(
            Debt_Position__c               = dp.Id,
            Fee_Amount__c                  = 50000,
            Capitalisation_Date__c         = Date.today(),
            Pre_Capitalisation_Notional__c = originalNotional,
            Post_Capitalisation_Notional__c = originalNotional + 50000,
            Status__c                      = 'Pending',
            Correlation_Id__c              = 'test-fce-corr'
        );
        insert fce;

        // Give DP Active schedule status so reamortisation proceeds
        TriggerContext.getInstance().bypassGuards = true;
        update new Debt_Position__c(Id = dp.Id, Schedule_Generation_Status__c = 'Active');
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        FeeCapitalisationService.activateCapitalisation(fce.Id);
        Test.stopTest();

        Debt_Position__c dpAfter = [SELECT Position_Notional__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.areEqual(1050000, dpAfter.Position_Notional__c,
            'Notional should be uplifted by 50,000 fee amount');

        Fee_Capitalisation_Event__c fceAfter = [SELECT Status__c FROM Fee_Capitalisation_Event__c WHERE Id = :fce.Id];
        Assert.areEqual('Active', fceAfter.Status__c, 'FCE should be Active after activation');
    }
}