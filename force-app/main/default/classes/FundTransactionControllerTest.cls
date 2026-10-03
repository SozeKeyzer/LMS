@IsTest
private class FundTransactionControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name                   = 'Test Investor Entity',
            Investor_Entity_ID__c  = 'TESTENT01'
        );
        insert acc;

        Funds__c fund = new Funds__c(Name = 'Test Fund Alpha');
        insert fund;

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Test FI Alpha');
        insert fi;

        Warehouse_Note__c wn = new Warehouse_Note__c(
            Name                    = 'Test WN Alpha',
            Financial_Instrument__c = fi.Id
        );
        insert wn;
    }

    // ─── saveTransaction ───────────────────────────────────────────────────────

    @IsTest
    static void testSaveTransaction_insert() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 50000,
            BDM__c                     = UserInfo.getUserId()
        );

        Test.startTest();
        Map<String, Object> result = FundTransactionController.saveTransaction(tx);
        Test.stopTest();

        System.assertEquals(true, result.get('saved'), 'Transaction should be saved');
        List<String> errors = (List<String>) result.get('errors');
        System.assert(errors.isEmpty(), 'No errors expected');
        System.assertNotEquals(null, tx.Id, 'Record should have been inserted');
    }

    @IsTest
    static void testSaveTransaction_update() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 50000,
            BDM__c                     = UserInfo.getUserId()
        );
        insert tx;

        tx.Amount__c = 99000;

        Test.startTest();
        Map<String, Object> result = FundTransactionController.saveTransaction(tx);
        Test.stopTest();

        System.assertEquals(true, result.get('saved'), 'Update should succeed');
        Fund_Transaction__c updated = [SELECT Amount__c FROM Fund_Transaction__c WHERE Id = :tx.Id];
        System.assertEquals(99000, updated.Amount__c, 'Amount should be updated');
    }

    // ─── saveBulk ──────────────────────────────────────────────────────────────

    @IsTest
    static void testSaveBulk_success() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        List<Fund_Transaction__c> records = new List<Fund_Transaction__c>();
        for (Integer i = 0; i < 5; i++) {
            records.add(new Fund_Transaction__c(
                Transaction_Date__c        = Date.today().addDays(i),
                Investment_Vehicle_Type__c = 'Fund',
                Fund__c                    = fund.Id,
                Investor_Entity__c         = acc.Id,
                Investor_Entity_ID__c = 'TESTENT01',
                Transaction_Type__c        = 'New Application',
                Amount__c                  = (i + 1) * 10000,
                BDM__c                     = UserInfo.getUserId()
            ));
        }

        Test.startTest();
        Map<String, Object> result = FundTransactionController.saveBulk(records);
        Test.stopTest();

        System.assertEquals(5, (Integer) result.get('saved'), 'All 5 records should be saved');
        List<String> errors = (List<String>) result.get('errors');
        System.assert(errors.isEmpty(), 'No errors expected');
    }

    @IsTest
    static void testSaveBulk_emptyList() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.saveBulk(new List<Fund_Transaction__c>());
        Test.stopTest();

        System.assertEquals(0, (Integer) result.get('saved'));
    }

    // ─── getTransactionById ────────────────────────────────────────────────────

    @IsTest
    static void testGetTransactionById() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 75000,
            BDM__c                     = UserInfo.getUserId()
        );
        insert tx;

        Test.startTest();
        Fund_Transaction__c result = FundTransactionController.getTransactionById(tx.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(tx.Id, result.Id);
        System.assertEquals(75000, result.Amount__c);
    }

    // ─── getTransactions ───────────────────────────────────────────────────────

    @IsTest
    static void testGetTransactions_noFilters() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        insert new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 10000,
            BDM__c                     = UserInfo.getUserId()
        );

        Test.startTest();
        Map<String, Object> result = FundTransactionController.getTransactions(
            null, null, null, false, 50, 0
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('records'));
        System.assertNotEquals(null, result.get('total'));
        Integer total = (Integer) result.get('total');
        System.assert(total >= 1, 'At least 1 record expected');
    }

    @IsTest
    static void testGetTransactions_withFundFilter() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        insert new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 10000,
            BDM__c                     = UserInfo.getUserId()
        );

        Test.startTest();
        Map<String, Object> result = FundTransactionController.getTransactions(
            new List<String>{ fund.Id }, null, null, false, 50, 0
        );
        Test.stopTest();

        List<Fund_Transaction__c> records = (List<Fund_Transaction__c>) result.get('records');
        System.assert(records.size() >= 1);
        System.assertEquals(fund.Id, records[0].Fund__c);
    }

    // ─── searchFinancialInstruments ────────────────────────────────────────────

    @IsTest
    static void testSearchFinancialInstruments() {
        Test.startTest();
        List<Financial_Instrument__c> results = FundTransactionController.searchFinancialInstruments('Test FI');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should find Test FI Alpha');
    }

    @IsTest
    static void testSearchFinancialInstruments_noMatch() {
        Test.startTest();
        List<Financial_Instrument__c> results = FundTransactionController.searchFinancialInstruments('ZZZNOMATCH999');
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    // ─── searchWarehouseNotes ──────────────────────────────────────────────────

    @IsTest
    static void testSearchWarehouseNotes() {
        Test.startTest();
        List<Warehouse_Note__c> results = FundTransactionController.searchWarehouseNotes('Test WN');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should find Test WN Alpha');
    }

    // ─── getFunds ──────────────────────────────────────────────────────────────

    @IsTest
    static void testGetFunds() {
        Test.startTest();
        List<Funds__c> results = FundTransactionController.getFunds();
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Should return at least Test Fund Alpha');
    }

    // ─── searchInvestorEntities ────────────────────────────────────────────────

    @IsTest
    static void testSearchInvestorEntities_byName() {
        Test.startTest();
        List<Account> results = FundTransactionController.searchInvestorEntities('Test Investor');
        Test.stopTest();

        System.assert(results.size() >= 1);
        System.assertEquals('TESTENT01', results[0].Investor_Entity_ID__c);
    }

    @IsTest
    static void testSearchInvestorEntities_byEntityId() {
        Test.startTest();
        List<Account> results = FundTransactionController.searchInvestorEntities('TESTENT01');
        Test.stopTest();

        System.assert(results.size() >= 1);
    }

    // ─── getEntityByExternalId ─────────────────────────────────────────────────

    @IsTest
    static void testGetEntityByExternalId_found() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getEntityByExternalId('TESTENT01');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('TESTENT01', result.get('entityId'));
        System.assertEquals('Test Investor Entity', result.get('name'));
    }

    @IsTest
    static void testGetEntityByExternalId_notFound() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getEntityByExternalId('DOESNOTEXIST');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testGetEntityByExternalId_blank() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getEntityByExternalId('');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testGetEntityByExternalId_whitespace() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getEntityByExternalId('  TESTENT01  ');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should trim whitespace and find record');
    }

    // ─── hasCustomPermission ───────────────────────────────────────────────────

    @IsTest
    static void testHasCustomPermission_unknownPerm() {
        Test.startTest();
        Boolean result = FundTransactionController.hasCustomPermission('Nonexistent_Permission_XYZ');
        Test.stopTest();

        System.assertEquals(false, result);
    }

    // ─── FundTransactionAuditLogger ────────────────────────────────────────────

    @IsTest
    static void testAuditLogger() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c        = Date.today(),
            Investment_Vehicle_Type__c = 'Fund',
            Fund__c                    = fund.Id,
            Investor_Entity__c         = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c        = 'New Application',
            Amount__c                  = 10000,
            BDM__c                     = UserInfo.getUserId()
        );
        Database.SaveResult[] results = Database.insert(
            new List<Fund_Transaction__c>{ tx }, false
        );

        Test.startTest();
        FundTransactionAuditLogger.logImport(1, 1, 'test_file.csv', results);
        Test.stopTest();

        List<Import_Audit_Log__c> logs = [
            SELECT Source_File_Name__c, Rows_In_File__c, Rows_Imported__c
            FROM Import_Audit_Log__c
            WHERE Source_File_Name__c = 'test_file.csv'
        ];
        System.assertEquals(1, logs.size(), 'One audit log should be created');
        System.assertEquals(1, logs[0].Rows_In_File__c);
        System.assertEquals(1, logs[0].Rows_Imported__c);
    }


    // ─── importCSVRaw ─────────────────────────────────────────────────────────

    @IsTest
    static void testImportCSVRaw_noPermission() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = 'noperm',
            Email             = 'noperm@test.example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'NoPermUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            UserName          = 'noperm' + DateTime.now().getTime() + '@test.example.com'
        );
        insert u;

        FundTransactionController.CSVImportRow row = new FundTransactionController.CSVImportRow();
        row.transactionDate = '2026-06-10';
        row.entityId        = 'TESTENT01';
        row.transactionType = 'New Application';
        row.amount          = 50000;
        row.rowIndex        = 0;

        Boolean threw = false;
        Test.startTest();
        System.runAs(u) {
            try {
                FundTransactionController.importCSVRaw(
                    new List<FundTransactionController.CSVImportRow>{ row },
                    'test.csv'
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Should throw AuraHandledException without Fund_Transaction_Importer permission');
    }

    @IsTest
    static void testImportCSVRaw_resolutionError() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Fund_Transactions_Importer' LIMIT 1];
        try { insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id); } catch (Exception e) { }

        FundTransactionController.CSVImportRow row = new FundTransactionController.CSVImportRow();
        row.transactionDate = '2026-06-10';
        row.fundName        = 'NONEXISTENT FUND XYZ';
        row.entityId        = 'NONEXISTENT999';
        row.transactionType = 'New Application';
        row.amount          = 50000;
        row.rowIndex        = 0;

        Map<String, Object> result;
        User me = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        Test.startTest();
        System.runAs(me) {
            result = FundTransactionController.importCSVRaw(
                new List<FundTransactionController.CSVImportRow>{ row },
                'test.csv'
            );
        }
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testImportCSVRaw_success() {
        // Use the current admin user (View All Data) so WITH USER_MODE queries resolve records
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Fund_Transactions_Importer' LIMIT 1];
        try { insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id); } catch (Exception e) { }

        Funds__c fund = [SELECT Id, Name FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id, Name FROM Financial_Instrument__c WHERE Name = 'Test FI Alpha' LIMIT 1];

        // Fund row
        FundTransactionController.CSVImportRow row1 = new FundTransactionController.CSVImportRow();
        row1.transactionDate = '2026-06-10';
        row1.fundName        = fund.Name;
        row1.entityId        = 'TESTENT01';
        row1.transactionType = 'New Application';
        row1.amount          = 100000;
        row1.bdmUsername     = UserInfo.getUserName();
        row1.rowIndex        = 0;

        // FI row — exercises the fiNames lookup block
        FundTransactionController.CSVImportRow row2 = new FundTransactionController.CSVImportRow();
        row2.transactionDate = '2026-06-11';
        row2.fiName          = fi.Name;
        row2.entityId        = 'TESTENT01';
        row2.transactionType = 'New Application';
        row2.amount          = 50000;
        row2.rowIndex        = 1;

        // No-vehicle row — exercises the else branch
        FundTransactionController.CSVImportRow row3 = new FundTransactionController.CSVImportRow();
        row3.entityId        = 'TESTENT01';
        row3.transactionType = 'New Application';
        row3.amount          = 10000;
        row3.rowIndex        = 2;

        Map<String, Object> result;
        User me = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        Test.startTest();
        System.runAs(me) {
            result = FundTransactionController.importCSVRaw(
                new List<FundTransactionController.CSVImportRow>{ row1, row2, row3 },
                'test.csv'
            );
        }
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // ─── getTransactions additional filter branches ────────────────────────────

    @IsTest
    static void testGetTransactions_withTxTypeFilter() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TESTENT01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Test Fund Alpha' LIMIT 1];
        insert new Fund_Transaction__c(
            Transaction_Date__c         = Date.today(),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'TESTENT01',
            Transaction_Type__c         = 'Fund Redemption',
            Amount__c                   = 5000,
            BDM__c                      = UserInfo.getUserId()
        );

        Test.startTest();
        Map<String, Object> result = FundTransactionController.getTransactions(
            null, new List<String>{ 'Fund Redemption' }, null, false, 50, 0
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('records'));
    }

    @IsTest
    static void testGetTransactions_withIntrafundFilter() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getTransactions(
            null, null, null, true, 50, 0
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('records'));
    }

    @IsTest
    static void testGetTransactions_withMonthFilter() {
        Test.startTest();
        Map<String, Object> result = FundTransactionController.getTransactions(
            null, null, new List<String>{ 'January 2026' }, false, 50, 0
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('records'));
    }
}
