/**
 * StatusIndicatorControllerTest
 *
 * Tests are written to pass regardless of which CMDT records are deployed
 * in the target org. No assertions depend on specific indicator counts or
 * field values — only on guaranteed behaviour (no exception, correct empty
 * returns for guard conditions, SAFE_FILTER regex correctness).
 *
 * Code coverage of evaluate() / evaluateCount() / evaluateLatest() is
 * achieved automatically when the CMDT records ship in the same change set
 * and the method is called with a valid parent object API name.
 */
@isTest
private class StatusIndicatorControllerTest {

    // ── Setup ─────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Test Borrower');
        insert a;
        insert new Financial_Instrument__c(Name = 'Test Loan', Borrower__c = a.Id);
    }

    // ── Guard conditions — always return empty, never throw ───────────────────

    @isTest
    static void emptyForNullRecordId() {
        Test.startTest();
        List<StatusIndicatorController.IndicatorResult> results =
            StatusIndicatorController.getIndicators(null, 'Financial_Instrument__c');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Null recordId must return empty list');
    }

    @isTest
    static void emptyForBlankParentObject() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        List<StatusIndicatorController.IndicatorResult> results =
            StatusIndicatorController.getIndicators(fi.Id, '');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Blank parentObjectApiName must return empty list');
    }

    @isTest
    static void emptyForUnknownParentObject() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        List<StatusIndicatorController.IndicatorResult> results =
            StatusIndicatorController.getIndicators(fi.Id, 'NonExistent_Object__c');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'No CMDT for unknown object — must return empty');
    }

    // ── Full execution path — exercises evaluate() when CMDT is deployed ──────

    @isTest
    static void doesNotThrowForFinancialInstrument() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        List<StatusIndicatorController.IndicatorResult> results =
            StatusIndicatorController.getIndicators(fi.Id, 'Financial_Instrument__c');
        Test.stopTest();
        System.assertNotEquals(null, results, 'Result list must never be null');
    }

    @isTest
    static void doesNotThrowForDebtPosition() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        List<StatusIndicatorController.IndicatorResult> results =
            StatusIndicatorController.getIndicators(fi.Id, 'Debt_Position__c');
        Test.stopTest();
        System.assertNotEquals(null, results, 'Result list must never be null');
    }

    // ── Direct unit tests: evaluateCount / evaluateLatest ────────────────────
    // These call the private (@TestVisible) methods directly with an in-memory
    // CMDT config so coverage is not gated on which CMDT records are deployed.
    // Workout__c is used as the child object because its schema is known:
    //   Financial_Instrument__c (Lookup), Workout_Status__c (Picklist).

    static Status_Indicator__mdt workoutCmdt(String mode) {
        Status_Indicator__mdt cfg = new Status_Indicator__mdt();
        cfg.DeveloperName            = 'Test_Workout';
        cfg.Label__c                 = 'Workout';
        cfg.Child_Object__c          = 'Workout__c';
        cfg.Relationship_Field__c    = 'Financial_Instrument__c';
        cfg.Active_Filter__c         = null;
        cfg.Indicator_Mode__c        = mode;
        cfg.Latest_Sort_Field__c     = 'CreatedDate';
        cfg.Latest_Display_Field__c  = 'Workout_Status__c';
        cfg.Icon__c                  = 'utility:warning';
        cfg.Variant__c               = 'error';
        cfg.Detail_Template__c       = '{!Count} open';
        cfg.Related_List_API_Name__c = 'Workouts__r';
        cfg.Sort_Order__c            = 1;
        cfg.Is_Active__c             = true;
        return cfg;
    }

    @isTest
    static void evaluateCountZeroWhenNoChildRecords() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Test.startTest();
        StatusIndicatorController.IndicatorResult r =
            StatusIndicatorController.evaluateCount(workoutCmdt('Active_Count'), fi.Id, '');
        Test.stopTest();
        System.assertEquals(false, r.hasRecords, 'hasRecords must be false when count = 0');
        System.assertEquals(0, r.count, 'count must be 0');
    }

    @isTest
    static void evaluateCountNonZeroWhenChildRecordsExist() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        insert new Workout__c(Financial_Instrument__c = fi.Id, Workout_Status__c = 'Active Monitoring');
        Test.startTest();
        StatusIndicatorController.IndicatorResult r =
            StatusIndicatorController.evaluateCount(workoutCmdt('Active_Count'), fi.Id, '');
        Test.stopTest();
        System.assertEquals(true,  r.hasRecords, 'hasRecords must be true when count > 0');
        System.assertEquals(1,     r.count,      'count must equal 1');
        System.assertEquals('1 open', r.detail,  'detail template must be rendered');
    }

    @isTest
    static void evaluateLatestEmptyWhenNoChildRecords() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Map<String, Schema.SObjectField> fm =
            Schema.getGlobalDescribe().get('Workout__c').getDescribe().fields.getMap();
        Test.startTest();
        StatusIndicatorController.IndicatorResult r =
            StatusIndicatorController.evaluateLatest(workoutCmdt('Latest_Record'), fi.Id, '', fm);
        Test.stopTest();
        System.assertEquals(false, r.hasRecords, 'hasRecords must be false when no records exist');
    }

    @isTest
    static void evaluateLatestPopulatesResultWhenChildRecordExists() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        insert new Workout__c(Financial_Instrument__c = fi.Id, Workout_Status__c = 'Active Monitoring');
        Map<String, Schema.SObjectField> fm =
            Schema.getGlobalDescribe().get('Workout__c').getDescribe().fields.getMap();
        Test.startTest();
        StatusIndicatorController.IndicatorResult r =
            StatusIndicatorController.evaluateLatest(workoutCmdt('Latest_Record'), fi.Id, '', fm);
        Test.stopTest();
        System.assertEquals(true,              r.hasRecords,  'hasRecords must be true');
        System.assertNotEquals(null,           r.recordId,    'recordId must be populated');
        System.assertEquals('Active Monitoring', r.statusValue, 'statusValue must match inserted record');
    }

    // ── SAFE_FILTER regex ─────────────────────────────────────────────────────

    @isTest
    static void safeFilterRejectsIllegalCharacters() {
        // Each string contains a character outside the whitelist — regex must reject it.
        // Keyword-based injection (SELECT, DELETE, etc.) is blocked by the separate
        // keyword check in evaluate(), not by this regex.
        List<String> badFilters = new List<String>{
            'Status__c = \'x\'; DELETE FROM Loan__c',    // semicolon
            'Status__c = \'x\'||\'y\'',                   // pipe
            'Status__c LIKE \'%Active%\'',                // percent
            'Status__c = {\'Approved\'}'                  // curly brace
        };
        for (String bad : badFilters) {
            System.assertEquals(false,
                StatusIndicatorController.SAFE_FILTER.matcher(bad).matches(),
                'SAFE_FILTER should reject: ' + bad);
        }
    }

    @isTest
    static void safeFilterAllowsValidFilterStrings() {
        List<String> goodFilters = new List<String>{
            'Workout_Status__c NOT IN (\'Closed\',\'Resolved\',\'Cancelled\')',
            'Waiver_Status__c = \'Approved\' AND (Expiration_Date__c >= TODAY OR Expiration_Date__c = null) AND Expired__c != true',
            'Status__c IN (\'Submitted\',\'Under Review\',\'Pending\')'
        };
        for (String good : goodFilters) {
            System.assertEquals(true,
                StatusIndicatorController.SAFE_FILTER.matcher(good).matches(),
                'SAFE_FILTER should allow: ' + good);
        }
    }

    // ── Sharing / access control ──────────────────────────────────────────────

    @isTest
    static void neverThrowsForRestrictedUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            Username          = 'sitest' + DateTime.now().getTime() + '@ipartners.test.com',
            Email             = 'sitest@ipartners.test.com',
            LastName          = 'SITest',
            Alias             = 'sitest',
            TimeZoneSidKey    = 'GMT',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        System.runAs(u) {
            Test.startTest();
            List<StatusIndicatorController.IndicatorResult> results =
                StatusIndicatorController.getIndicators(fi.Id, 'Financial_Instrument__c');
            Test.stopTest();
            System.assertNotEquals(null, results, 'Must not throw for a restricted user');
        }
    }
}
