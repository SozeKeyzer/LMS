@IsTest
private class FundTransactionAnalyticsControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name                  = 'Analytics Test Entity',
            Investor_Entity_ID__c = 'ANALTEST01'
        );
        insert acc;

        Funds__c fund = new Funds__c(Name = 'Analytics Test Fund');
        insert fund;

        List<Fund_Transaction__c> txs = new List<Fund_Transaction__c>();

        txs.add(new Fund_Transaction__c(
            Transaction_Date__c         = Date.newInstance(2026, 6, 1),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'ANALTEST01',
            Transaction_Type__c         = 'New Application',
            Amount__c                   = 50000,
            BDM__c                      = UserInfo.getUserId()
        ));

        txs.add(new Fund_Transaction__c(
            Transaction_Date__c         = Date.newInstance(2026, 6, 15),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'ANALTEST01',
            Transaction_Type__c         = 'Fund Redemption',
            Amount__c                   = 20000,
            BDM__c                      = UserInfo.getUserId()
        ));

        txs.add(new Fund_Transaction__c(
            Transaction_Date__c         = Date.newInstance(2026, 5, 10),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'ANALTEST01',
            Transaction_Type__c         = 'Fund Switch In',
            Amount__c                   = 30000,
            BDM__c                      = UserInfo.getUserId()
        ));

        txs.add(new Fund_Transaction__c(
            Transaction_Date__c         = Date.newInstance(2026, 5, 10),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'ANALTEST01',
            Transaction_Type__c         = 'Fund Switch Out',
            Amount__c                   = 30000,
            BDM__c                      = UserInfo.getUserId()
        ));

        insert txs;
    }

    // ─── getAvailableMonths ────────────────────────────────────────────────────

    @IsTest
    static void testGetAvailableMonths_returnsMonths() {
        Test.startTest();
        List<String> months = FundTransactionAnalyticsController.getAvailableMonths();
        Test.stopTest();

        System.assertNotEquals(null, months);
        System.assert(months.size() >= 1, 'Should return months from test data');
        for (String m : months) {
            System.assert(m.contains('-'), 'Each month key should be in YYYY-M format, got: ' + m);
        }
    }

    // ─── getFundFlowSummary ────────────────────────────────────────────────────

    @IsTest
    static void testGetFundFlowSummary_noFilters() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getFundFlowSummary('', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return grouped fund flow rows');
    }

    @IsTest
    static void testGetFundFlowSummary_withMonthFilter() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getFundFlowSummary('2026-6', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return June 2026 transactions');
        for (AggregateResult r : results) {
            System.assertNotEquals(null, r.get('txType'));
        }
    }

    @IsTest
    static void testGetFundFlowSummary_withFundFilter() {
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Analytics Test Fund' LIMIT 1];

        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getFundFlowSummary('', fund.Id);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1);
        for (AggregateResult r : results) {
            System.assertEquals(fund.Id, r.get('fundId'));
        }
    }

    @IsTest
    static void testGetFundFlowSummary_noMatchingMonth() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getFundFlowSummary('1900-1', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(0, results.size(), 'Should return no rows for non-existent month');
    }

    // ─── getBDMPerformance ─────────────────────────────────────────────────────

    @IsTest
    static void testGetBDMPerformance_noFilters() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getBDMPerformance('', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return BDM rows');
    }

    @IsTest
    static void testGetBDMPerformance_withMonthFilter() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getBDMPerformance('2026-6', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
    }

    @IsTest
    static void testGetBDMPerformance_withFundFilter() {
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Analytics Test Fund' LIMIT 1];

        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getBDMPerformance('', fund.Id);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1);
    }

    // ─── getTransactionBreakdown ───────────────────────────────────────────────

    @IsTest
    static void testGetTransactionBreakdown_noFilters() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getTransactionBreakdown('', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return breakdown rows');
        AggregateResult first = results[0];
        System.assertNotEquals(null, first.get('yr'), 'yr field should be present');
        System.assertNotEquals(null, first.get('mo'), 'mo field should be present');
    }

    @IsTest
    static void testGetTransactionBreakdown_withFundFilter() {
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Analytics Test Fund' LIMIT 1];

        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getTransactionBreakdown(fund.Id, '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1);
    }

    @IsTest
    static void testGetTransactionBreakdown_withMonthFilter() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getTransactionBreakdown('', '2026-5');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return May 2026 rows');
        AggregateResult first = results[0];
        System.assertEquals(2026, first.get('yr'));
        System.assertEquals(5, first.get('mo'));
    }

    // ─── getSwitchFlowMap ──────────────────────────────────────────────────────

    @IsTest
    static void testGetSwitchFlowMap_noFilters() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getSwitchFlowMap('', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return Fund Switch In and Out rows');
        for (AggregateResult r : results) {
            String txType = (String) r.get('txType');
            System.assert(
                txType == 'Fund Switch In' || txType == 'Fund Switch Out',
                'Only switch types should appear'
            );
        }
    }

    @IsTest
    static void testGetSwitchFlowMap_withMonthFilter() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getSwitchFlowMap('2026-5', '');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Switch transactions in May 2026 should appear');
    }

    @IsTest
    static void testGetSwitchFlowMap_withFundFilter() {
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Analytics Test Fund' LIMIT 1];

        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getSwitchFlowMap('', fund.Id);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1);
    }

    @IsTest
    static void testGetSwitchFlowMap_noSwitchMonth() {
        Test.startTest();
        List<AggregateResult> results = FundTransactionAnalyticsController.getSwitchFlowMap('2026-6', '');
        Test.stopTest();

        // June 2026 has no switch transactions in test data
        System.assertNotEquals(null, results);
        System.assertEquals(0, results.size(), 'No switch transactions in June 2026');
    }
}
