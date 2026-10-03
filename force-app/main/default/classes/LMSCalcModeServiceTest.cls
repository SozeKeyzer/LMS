/**
 * LMSCalcModeServiceTest
 * Covers: CalcModeService — enterManualMode, activateManualMode, returnToEngineMode
 */
@IsTest
private class LMSCalcModeServiceTest {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'CalcMode FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'CalcMode DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Active',
            Calc_Mode__c             = 'Engine',
            iPlatform_External_Id__c = 'CMODE-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ─── CalcModeService.enterManualMode ─────────────────────────────────────

    @IsTest
    static void testEnterManualMode_CreatesPendingApprovalEpisode() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Test.startTest();
        CalcModeService.enterManualMode(
            dp.Id, 'Debt_Position__c', 'Audit', 'Testing manual mode', 30
        );
        Test.stopTest();

        List<Calc_Mode_Change__c> episodes = [
            SELECT Id, Status__c, Mode_From__c, Mode_To__c
            FROM Calc_Mode_Change__c WHERE Debt_Position__c = :dp.Id
        ];
        Assert.isFalse(episodes.isEmpty(), 'enterManualMode must create a Calc_Mode_Change__c episode');
        Assert.areEqual('Pending_Approval', episodes[0].Status__c);
        Assert.areEqual('Engine', episodes[0].Mode_From__c);
        Assert.areEqual('Manual', episodes[0].Mode_To__c);
    }

    // ─── CalcModeService.activateManualMode ──────────────────────────────────

    @IsTest
    static void testActivateManualMode_SetsCalcModeManual() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        CalcModeService.enterManualMode(
            dp.Id, 'Debt_Position__c', 'Audit', 'Manual mode activation test', 14
        );
        Calc_Mode_Change__c episode = [SELECT Id FROM Calc_Mode_Change__c WHERE Debt_Position__c = :dp.Id LIMIT 1];

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcModeService.activateManualMode(episode.Id);
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Debt_Position__c dpAfter = [SELECT Calc_Mode__c, Active_Mode_Change__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.areEqual('Manual', dpAfter.Calc_Mode__c, 'activateManualMode must set Calc_Mode to Manual');
        Assert.areEqual(episode.Id, dpAfter.Active_Mode_Change__c, 'Active_Mode_Change__c must reference the episode');

        Calc_Mode_Change__c epAfter = [SELECT Status__c FROM Calc_Mode_Change__c WHERE Id = :episode.Id];
        Assert.areEqual('Active', epAfter.Status__c, 'Episode must be in Active status after activation');
    }

    // ─── CalcModeService.returnToEngineMode ──────────────────────────────────

    @IsTest
    static void testReturnToEngineMode_SetsCalcModeEngine() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        CalcModeService.enterManualMode(
            dp.Id, 'Debt_Position__c', 'Return test', 'Returning to engine', 7
        );
        Calc_Mode_Change__c episode = [SELECT Id FROM Calc_Mode_Change__c WHERE Debt_Position__c = :dp.Id LIMIT 1];

        TriggerContext.getInstance().bypassGuards = true;
        CalcModeService.activateManualMode(episode.Id);
        TriggerContext.getInstance().bypassGuards = false;

        Test.startTest();
        TriggerContext.getInstance().bypassGuards = true;
        CalcModeService.returnToEngineMode(episode.Id, 'Engine', 'Period ended');
        TriggerContext.getInstance().bypassGuards = false;
        Test.stopTest();

        Debt_Position__c dpAfter = [SELECT Calc_Mode__c, Active_Mode_Change__c FROM Debt_Position__c WHERE Id = :dp.Id];
        Assert.areEqual('Engine', dpAfter.Calc_Mode__c, 'returnToEngineMode must restore Calc_Mode to Engine');
        Assert.isNull(dpAfter.Active_Mode_Change__c, 'Active_Mode_Change__c must be cleared on return');

        Calc_Mode_Change__c epAfter = [SELECT Status__c FROM Calc_Mode_Change__c WHERE Id = :episode.Id];
        Assert.areEqual('Closed', epAfter.Status__c, 'Episode must be Closed after return to engine');
    }

    @IsTest
    static void testEnterManualMode_FinancialInstrument_CreatesEpisode() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];

        Test.startTest();
        CalcModeService.enterManualMode(
            fi.Id, 'Financial_Instrument__c', 'Audit', 'FI-level manual mode', 5
        );
        Test.stopTest();

        List<Calc_Mode_Change__c> episodes = [
            SELECT Id, Status__c FROM Calc_Mode_Change__c
            WHERE Financial_Instrument__c = :fi.Id
        ];
        Assert.isFalse(episodes.isEmpty(), 'enterManualMode on FI must create episode linked to FI');
        Assert.areEqual('Pending_Approval', episodes[0].Status__c);
    }

}