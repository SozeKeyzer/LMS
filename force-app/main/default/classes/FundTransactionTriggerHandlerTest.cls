@IsTest
private class FundTransactionTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name                  = 'Trigger Test Entity',
            Investor_Entity_ID__c = 'TRIGTEST01'
        );
        insert acc;

        Funds__c fund = new Funds__c(Name = 'Trigger Test Fund');
        insert fund;
    }

    @IsTest
    static void testSetOwner_setsOwnerIdToBDM() {
        Id bdmId = UserInfo.getUserId();

        Fund_Transaction__c tx = new Fund_Transaction__c(BDM__c = bdmId);
        List<Fund_Transaction__c> records = new List<Fund_Transaction__c>{ tx };

        Test.startTest();
        FundTransactionTriggerHandler.setOwner(records);
        Test.stopTest();

        System.assertEquals(bdmId, records[0].OwnerId, 'OwnerId should be set to BDM Id');
    }

    @IsTest
    static void testSetOwner_nullBDM_doesNotChange() {
        Fund_Transaction__c tx = new Fund_Transaction__c();
        Id originalOwner = tx.OwnerId;
        List<Fund_Transaction__c> records = new List<Fund_Transaction__c>{ tx };

        Test.startTest();
        FundTransactionTriggerHandler.setOwner(records);
        Test.stopTest();

        System.assertEquals(originalOwner, records[0].OwnerId, 'OwnerId should not change when BDM is null');
    }

    @IsTest
    static void testSetOwner_emptyList() {
        Test.startTest();
        FundTransactionTriggerHandler.setOwner(new List<Fund_Transaction__c>());
        Test.stopTest();

        System.assert(true, 'Empty list should be handled without error');
    }

    @IsTest
    static void testSetOwner_viaTrigger_onInsert() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TRIGTEST01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Trigger Test Fund' LIMIT 1];
        Id bdmId      = UserInfo.getUserId();

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c         = Date.today(),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'TRIGTEST01',
            Transaction_Type__c         = 'New Application',
            Amount__c                   = 25000,
            BDM__c                      = bdmId
        );

        Test.startTest();
        insert tx;
        Test.stopTest();

        Fund_Transaction__c result = [SELECT OwnerId FROM Fund_Transaction__c WHERE Id = :tx.Id];
        System.assertEquals(bdmId, result.OwnerId, 'Trigger should set OwnerId to BDM on insert');
    }

    @IsTest
    static void testSetOwner_viaTrigger_onUpdate() {
        Account  acc  = [SELECT Id FROM Account WHERE Investor_Entity_ID__c = 'TRIGTEST01' LIMIT 1];
        Funds__c fund = [SELECT Id FROM Funds__c WHERE Name = 'Trigger Test Fund' LIMIT 1];
        Id bdmId      = UserInfo.getUserId();

        Fund_Transaction__c tx = new Fund_Transaction__c(
            Transaction_Date__c         = Date.today(),
            Investment_Vehicle_Type__c  = 'Fund',
            Fund__c                     = fund.Id,
            Investor_Entity__c          = acc.Id,
            Investor_Entity_ID__c = 'TRIGTEST01',
            Transaction_Type__c         = 'New Application',
            Amount__c                   = 10000,
            BDM__c                      = bdmId
        );
        insert tx;

        tx.Amount__c = 20000;

        Test.startTest();
        update tx;
        Test.stopTest();

        Fund_Transaction__c result = [SELECT OwnerId FROM Fund_Transaction__c WHERE Id = :tx.Id];
        System.assertEquals(bdmId, result.OwnerId, 'OwnerId should remain set to BDM after update');
    }
}
