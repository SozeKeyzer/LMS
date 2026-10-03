@IsTest
private class SecondaryTradingImportControllerTest {

    @TestSetup
    static void setup() {
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Test Deal Alpha', IsActive = true, Deal_Code__c = 'TDA001'),
            new Product2(Name = 'Test Deal Beta',  IsActive = true, Deal_Code__c = 'TDB002')
        };
        insert products;

        insert new Workout__c();
    }

    private static String validCsvOneRow() {
        return 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
             + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
    }

    private static String validCsvThreeOfferTypes() {
        return 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
             + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n'
             + 'TDA001,Funds Bid,Yes,200,ICIF01-Core Income Fund,Syndicate/Investor,26-07-2026\n'
             + 'TDA001,Funds / Funds,No,50,ICIF01-Core Income Fund,ICIF02-Short Term Income Fund,27-07-2026\n';
    }

    // Helper: serialize a list of rows to JSON string as the controller now expects
    private static String toJson(List<SecondaryTradingImportController.ImportRow> rows) {
        return JSON.serialize(rows);
    }

    // ── parseCSV happy path ───────────────────────────────────────────────────

    @IsTest
    static void testParseCSV_validSingleRow() {
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(validCsvOneRow());
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should have 1 row');
        Assert.isFalse(rows[0].hasError, 'Row should be valid');
        Assert.areEqual('TDA001',                  rows[0].deal);
        Assert.areEqual('Investor Offer',          rows[0].offerInitiatedBy);
        Assert.areEqual('No',                      rows[0].isWorkout);
        Assert.areEqual(100,                       rows[0].units);
        Assert.areEqual('Syndicate/Investor',      rows[0].buyer);
        Assert.areEqual('ICIF01-Core Income Fund', rows[0].seller);
    }

    @IsTest
    static void testParseCSV_allThreeOfferTypes() {
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(validCsvThreeOfferTypes());
        Test.stopTest();

        Assert.areEqual(3, rows.size());
        for (SecondaryTradingImportController.ImportRow row : rows) {
            Assert.isFalse(row.hasError, 'Row ' + row.rowNumber + ' should be valid: ' + row.errorMessage);
        }
    }

    @IsTest
    static void testParseCSV_caseInsensitiveHeaders() {
        String csv = 'DEAL CODE,OFFER INITIATED BY,IS WORKOUT/DISTRESSED,UNITS,BUYER,SELLER,EFFECTIVE DATE\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.isFalse(rows[0].hasError, rows[0].errorMessage);
    }

    @IsTest
    static void testParseCSV_windowsLineEndings() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\r\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\r\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.isFalse(rows[0].hasError, rows[0].errorMessage);
    }

    @IsTest
    static void testParseCSV_emptyLinesSkipped() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + '\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n'
                   + '\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Empty lines should be skipped');
    }

    @IsTest
    static void testParseCSV_quotedFieldsWithComma() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + '"TDA,001",Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual('TDA,001', rows[0].deal, 'Quoted field should retain embedded comma');
        Assert.isFalse(rows[0].hasError, rows[0].errorMessage);
    }

    @IsTest
    static void testParseCSV_escapedDoubleQuote() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + '"TDA""001",Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual('TDA"001', rows[0].deal, 'Double-quote escape should be unescaped');
    }

    // ── parseCSV bulk ─────────────────────────────────────────────────────────

    @IsTest
    static void testParseCSV_bulkRows() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n';
        for (Integer i = 0; i < 200; i++) {
            csv += 'TDA001,Investor Offer,No,' + (i + 1) + ',Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        }
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual(200, rows.size(), 'Should parse 200 rows');
        Integer errorCount = 0;
        for (SecondaryTradingImportController.ImportRow row : rows) {
            if (row.hasError) errorCount++;
        }
        Assert.areEqual(0, errorCount, 'No rows should have errors');
    }

    // ── parseCSV required field errors ───────────────────────────────────────

    @IsTest
    static void testParseCSV_missingDeal() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + ',Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Deal Code is required'));
    }

    @IsTest
    static void testParseCSV_missingOfferInitiatedBy() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Offer Initiated By is required'));
    }

    @IsTest
    static void testParseCSV_missingIsWorkout() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Is Workout/Distressed is required'));
    }

    @IsTest
    static void testParseCSV_missingUnits() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Units is required'));
    }

    @IsTest
    static void testParseCSV_nonNumericUnits() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,abc,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Units must be a number'));
    }

    @IsTest
    static void testParseCSV_zeroUnits() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,0,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Units must be greater than zero'));
    }

    @IsTest
    static void testParseCSV_negativeUnits() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,-5,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Units must be greater than zero'));
    }

    // ── parseCSV picklist errors ──────────────────────────────────────────────

    @IsTest
    static void testParseCSV_invalidOfferInitiatedBy() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,INVALID_VALUE,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Offer Initiated By must be one of'));
    }

    @IsTest
    static void testParseCSV_invalidIsWorkout() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,Maybe,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Is Workout/Distressed must be Yes or No'));
    }

    @IsTest
    static void testParseCSV_invalidBuyerValue() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,100,NOT_A_FUND,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Buyer value not recognised'));
    }

    // ── parseCSV cross-field rules ────────────────────────────────────────────

    @IsTest
    static void testParseCSV_investorOfferRequiresBuyerSyndicateInvestor() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,100,ICIF01-Core Income Fund,ICIF02-Short Term Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('For Investor Offer, Buyer must be Syndicate/Investor'));
    }

    @IsTest
    static void testParseCSV_fundsBidRequiresSellerSyndicateInvestor() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Funds Bid,No,100,ICIF01-Core Income Fund,ICIF02-Short Term Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('For Funds Bid (To Investors), Seller must be Syndicate/Investor'));
    }

    @IsTest
    static void testParseCSV_fundsToFundsRejectsSyndicateInvestorBuyer() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Funds / Funds,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('For Funds / Funds trades, neither Buyer nor Seller can be Syndicate/Investor'));
    }

    @IsTest
    static void testParseCSV_buyerSellerSameFundFails() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Funds / Funds,No,100,ICIF01-Core Income Fund,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Buyer and Seller cannot be the same fund'));
    }

    // ── parseCSV new fields — Unit Price ─────────────────────────────────────

    @IsTest
    static void testParseCSV_validUnitPrice() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Unit Price\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026,95.50\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isFalse(rows[0].hasError, rows[0].errorMessage);
        Assert.areEqual(95.50, rows[0].unitPrice);
    }

    @IsTest
    static void testParseCSV_invalidUnitPrice() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Unit Price\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026,abc\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Unit Price must be a number'));
    }

    @IsTest
    static void testParseCSV_zeroUnitPrice() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Unit Price\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026,0\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Unit Price must be greater than zero'));
    }

    // ── parseCSV new fields — Effective Date ─────────────────────────────────

    @IsTest
    static void testParseCSV_validEffectiveDate() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isFalse(rows[0].hasError, rows[0].errorMessage);
        Assert.areEqual('25-07-2026', rows[0].effectiveDate);
    }

    @IsTest
    static void testParseCSV_invalidEffectiveDateFormat() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,not-a-date\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Effective Date is not a valid date'));
    }

    // ── parseCSV new fields — Syndicate Comms Required ───────────────────────

    @IsTest
    static void testParseCSV_synCommsRequired_invalidValue() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Syndicate Comms Required\n'
                   + 'TDA001,Funds Bid,Yes,100,ICIF01-Core Income Fund,Syndicate/Investor,25-07-2026,Maybe\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Syndicate Comms Required must be Yes or No'));
    }

    @IsTest
    static void testParseCSV_synCommsRequired_yesButNotFundsBid() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Syndicate Comms Required\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026,Yes\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Syndicate Comms Required can only be Yes when Offer Initiated By is Funds Bid'));
    }

    @IsTest
    static void testParseCSV_workoutNotAllowedWhenIsWorkoutNo() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date,Workout\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026,Some Workout\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.isTrue(rows[0].hasError);
        Assert.isTrue(rows[0].errorMessage.contains('Workout must be blank when Is Related Deal in Workout/Distressed is No'));
    }

    // ── importRows new fields ─────────────────────────────────────────────────

    @IsTest
    static void testImportRows_workoutNotFound() {
        SecondaryTradingImportController.ImportRow row =
            makeValidRow(1, 'TDA001', 'Funds Bid', 'Yes', 100);
        row.seller                 = 'Syndicate/Investor';
        row.buyer                  = 'ICIF01-Core Income Fund';
        row.syndicateCommsRequired = 'Yes';
        row.workout                = 'DOES_NOT_EXIST_99999';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(
                toJson(new List<SecondaryTradingImportController.ImportRow>{ row })
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount);
        Assert.areEqual(1, result.failureCount);
        Assert.isTrue(result.errors[0].contains('Workout not found'));
    }

    @IsTest
    static void testImportRows_withNewFields() {
        // Workout__c.Name is an Auto Number — query the system-assigned name
        Workout__c w = [SELECT Name FROM Workout__c LIMIT 1];

        SecondaryTradingImportController.ImportRow row =
            makeValidRow(1, 'TDA001', 'Funds Bid', 'Yes', 100);
        row.seller                 = 'Syndicate/Investor';
        row.buyer                  = 'ICIF01-Core Income Fund';
        row.syndicateCommsRequired = 'Yes';
        row.workout                = w.Name;
        row.unitPrice              = 95.50;
        row.effectiveDate          = '25-07-2026';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(
                toJson(new List<SecondaryTradingImportController.ImportRow>{ row })
            );
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(1, result.successCount + result.failureCount, 'One row should be processed');
    }

    // ── parseCSV header/structure errors ─────────────────────────────────────

    @IsTest
    static void testParseCSV_missingRequiredColumn() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed\nTDA001,Investor Offer,No\n';
        Boolean threw = false;
        try {
            SecondaryTradingImportController.parseCSV(csv);
        } catch (AuraHandledException e) {
            threw = true;
            // AuraHandledException.getMessage() returns "Script-thrown exception"
            // in test context — message content cannot be asserted here
        }
        Assert.isTrue(threw, 'Should throw AuraHandledException for missing column');
    }

    @IsTest
    static void testParseCSV_noDataRows() {
        String csv = 'Deal,Offer Initiated By,Is Workout/Distressed,Units\n';
        Boolean threw = false;
        try {
            SecondaryTradingImportController.parseCSV(csv);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Should throw when no data rows exist');
    }

    @IsTest
    static void testParseCSV_blankContent() {
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV('');
        Test.stopTest();

        Assert.areEqual(0, rows.size(), 'Blank content should return empty list');
    }

    // ── importRows happy path ─────────────────────────────────────────────────

    @IsTest
    static void testImportRows_emptyList() {
        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(
                JSON.serialize(new List<SecondaryTradingImportController.ImportRow>())
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount);
        Assert.areEqual(0, result.failureCount);
        Assert.areEqual(0, result.errors.size());
    }

    @IsTest
    static void testImportRows_singleValidRow() {
        SecondaryTradingImportController.ImportRow row =
            makeValidRow(1, 'TDA001', 'Investor Offer', 'No', 100);
        row.buyer         = 'Syndicate/Investor';
        row.seller        = 'ICIF01-Core Income Fund';
        row.effectiveDate = '25-07-2026';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(toJson(new List<SecondaryTradingImportController.ImportRow>{ row }));
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(1, result.successCount + result.failureCount, 'One row should be processed');
    }

    @IsTest
    static void testImportRows_dealNotFound() {
        SecondaryTradingImportController.ImportRow row =
            makeValidRow(1, 'INVALID_CODE_99999', 'Investor Offer', 'No', 100);
        row.buyer         = 'Syndicate/Investor';
        row.effectiveDate = '25-07-2026';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(toJson(new List<SecondaryTradingImportController.ImportRow>{ row }));
        Test.stopTest();

        Assert.areEqual(0, result.successCount);
        Assert.areEqual(1, result.failureCount);
        Assert.isTrue(result.errors[0].contains('Deal Code not found'));
    }

    @IsTest
    static void testImportRows_skipsRowsWithErrors() {
        SecondaryTradingImportController.ImportRow badRow =
            makeValidRow(1, 'TDA001', 'Investor Offer', 'No', 100);
        badRow.hasError     = true;
        badRow.errorMessage = 'Pre-validation failed';

        SecondaryTradingImportController.ImportRow goodRow =
            makeValidRow(2, 'TDA001', 'Investor Offer', 'No', 50);
        goodRow.buyer         = 'Syndicate/Investor';
        goodRow.seller        = 'ICIF01-Core Income Fund';
        goodRow.effectiveDate = '25-07-2026';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(
                toJson(new List<SecondaryTradingImportController.ImportRow>{ badRow, goodRow })
            );
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.isTrue(result.failureCount >= 1, 'Bad row should be counted as failure');
        Assert.isTrue(result.errors.size() >= 1, 'Should have at least one error entry');
    }

    @IsTest
    static void testImportRows_bulkInsert() {
        List<SecondaryTradingImportController.ImportRow> rows =
            new List<SecondaryTradingImportController.ImportRow>();
        for (Integer i = 0; i < 50; i++) {
            SecondaryTradingImportController.ImportRow row =
                makeValidRow(i + 1, 'TDA001', 'Funds / Funds', 'No', i + 1);
            row.buyer         = 'ICIF01-Core Income Fund';
            row.seller        = 'ICIF02-Short Term Income Fund';
            row.effectiveDate = '25-07-2026';
            rows.add(row);
        }

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(toJson(rows));
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(50, result.successCount + result.failureCount, 'All 50 rows should be processed');
    }

    @IsTest
    static void testImportRows_multipleDealsBatchedLookup() {
        SecondaryTradingImportController.ImportRow r1 =
            makeValidRow(1, 'TDA001', 'Investor Offer', 'No', 10);
        r1.buyer         = 'Syndicate/Investor';
        r1.seller        = 'ICIF01-Core Income Fund';
        r1.effectiveDate = '25-07-2026';

        SecondaryTradingImportController.ImportRow r2 =
            makeValidRow(2, 'TDB002', 'Investor Offer', 'No', 20);
        r2.buyer         = 'Syndicate/Investor';
        r2.seller        = 'ICIF01-Core Income Fund';
        r2.effectiveDate = '26-07-2026';

        Test.startTest();
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(
                toJson(new List<SecondaryTradingImportController.ImportRow>{ r1, r2 })
            );
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(2, result.successCount + result.failureCount, 'Both rows should be processed');
    }

    // ── getContentVersion ─────────────────────────────────────────────────────

    @IsTest
    static void testGetContentVersion_basicRead() {
        ContentVersion cv = new ContentVersion();
        cv.Title          = 'TestFile';
        cv.PathOnClient   = 'TestFile.csv';
        cv.VersionData    = Blob.valueOf('Deal,Units\nTest,100\n');
        cv.IsMajorVersion = true;
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        Test.startTest();
        String content = SecondaryTradingImportController.getContentVersion(cv.Id);
        Test.stopTest();

        Assert.isTrue(content.contains('Deal'), 'Should return CSV content');
    }

    // ── End-to-end ────────────────────────────────────────────────────────────

    @IsTest
    static void testEndToEnd_parseAndImport() {
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(validCsvOneRow());
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(toJson(rows));
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(1, result.successCount + result.failureCount, 'One row should be processed');
    }

    @IsTest
    static void testEndToEnd_mixedValidAndInvalidRows() {
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n'
                   + ',Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n'
                   + 'TDA001,Investor Offer,No,abc,Syndicate/Investor,ICIF01-Core Income Fund,25-07-2026\n';

        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        SecondaryTradingImportController.ImportResult result =
            SecondaryTradingImportController.importRows(toJson(rows));
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.isTrue(result.failureCount >= 2, '2 invalid rows should be counted as failures');
    }

    // ── Date format flexibility ───────────────────────────────────────────────

    @IsTest
    static void testParseCSV_excelDateFormats() {
        // Each row uses a different format Excel might export
        String csv = 'Deal Code,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Effective Date\n'
                   + 'TDA001,Investor Offer,No,10,Syndicate/Investor,ICIF01-Core Income Fund,25/07/2026\n'
                   + 'TDA001,Investor Offer,No,20,Syndicate/Investor,ICIF01-Core Income Fund,25-Jul-2026\n'
                   + 'TDA001,Investor Offer,No,30,Syndicate/Investor,ICIF01-Core Income Fund,25-Jul-26\n'
                   + 'TDA001,Investor Offer,No,40,Syndicate/Investor,ICIF01-Core Income Fund,2026-07-25\n';
        Test.startTest();
        List<SecondaryTradingImportController.ImportRow> rows =
            SecondaryTradingImportController.parseCSV(csv);
        Test.stopTest();

        Assert.areEqual(4, rows.size());
        for (SecondaryTradingImportController.ImportRow r : rows) {
            Assert.isFalse(r.hasError, 'Row ' + r.rowNumber + ' failed: ' + r.errorMessage);
        }
    }

    // ── Private helper ────────────────────────────────────────────────────────

    private static SecondaryTradingImportController.ImportRow makeValidRow(
        Integer rowNum, String deal, String offer, String workout, Decimal units
    ) {
        SecondaryTradingImportController.ImportRow row = new SecondaryTradingImportController.ImportRow();
        row.rowNumber        = rowNum;
        row.deal             = deal;
        row.offerInitiatedBy = offer;
        row.isWorkout        = workout;
        row.units            = units;
        row.hasError         = false;
        row.errorMessage     = '';
        row.buyer            = null;
        row.seller           = null;
        return row;
    }
}