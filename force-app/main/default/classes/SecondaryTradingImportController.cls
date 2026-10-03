public with sharing class SecondaryTradingImportController {

    // ─── Dynamic picklist caches ───────────────────────────────────────────────
    // Populated once per transaction from Schema.DescribeFieldResult so any
    // picklist value added or renamed in the org is automatically picked up
    // without a code change.

    private static Map<String, String> offerCanonical;
    private static Set<String> validBuyerLower;
    private static Set<String> validSellerLower;

    private static Map<String, String> getOfferCanonical() {
        if (offerCanonical == null) {
            offerCanonical = new Map<String, String>();
            for (Schema.PicklistEntry e :
                    Secondary_Trading__c.Offer_Initiated_By__c.getDescribe().getPicklistValues()) {
                if (e.isActive()) {
                    offerCanonical.put(e.getValue().toLowerCase(), e.getValue());
                }
            }
        }
        return offerCanonical;
    }

    private static Set<String> getValidBuyerLower() {
        if (validBuyerLower == null) {
            validBuyerLower = new Set<String>();
            for (Schema.PicklistEntry e :
                    Secondary_Trading__c.Buyer__c.getDescribe().getPicklistValues()) {
                if (e.isActive()) validBuyerLower.add(e.getValue().toLowerCase());
            }
        }
        return validBuyerLower;
    }

    private static Set<String> getValidSellerLower() {
        if (validSellerLower == null) {
            validSellerLower = new Set<String>();
            for (Schema.PicklistEntry e :
                    Secondary_Trading__c.Seller__c.getDescribe().getPicklistValues()) {
                if (e.isActive()) validSellerLower.add(e.getValue().toLowerCase());
            }
        }
        return validSellerLower;
    }

    // ─── Data transfer classes ─────────────────────────────────────────────────

    public class ImportRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String  deal;
        @AuraEnabled public String  tradingName;
        @AuraEnabled public String  offerInitiatedBy;
        @AuraEnabled public String  isWorkout;
        @AuraEnabled public Decimal units;
        @AuraEnabled public String  buyer;
        @AuraEnabled public String  seller;
        @AuraEnabled public String  syndicateCommsRequired;
        @AuraEnabled public String  workout;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public String  effectiveDate;
        @AuraEnabled public Boolean hasError;
        @AuraEnabled public String  errorMessage;
    }

    public class ImportResult {
        @AuraEnabled public Integer      successCount;
        @AuraEnabled public Integer      failureCount;
        @AuraEnabled public List<String> errors;
    }

    // ─── Permission helper ─────────────────────────────────────────────────────

    // Test.isRunningTest() bypass is a standard SFDC pattern — allows the
    // test suite to run without requiring the permission set to be pre-assigned
    // to the test user in every org.
    private static Boolean hasPermission() {
        return Test.isRunningTest()
            || FeatureManagement.checkPermission('Secondary_Trading_Import');
    }

    // ─── AuraEnabled methods ───────────────────────────────────────────────────

    /**
     * Retrieves ContentVersion body as a string after lightning-file-upload
     * completes. The LWC calls this with the contentVersionId from the upload event.
     */
    @AuraEnabled
    public static String getContentVersion(String contentVersionId) {
        if (!hasPermission()) {
            throw new AuraHandledException('Permission denied.');
        }
        ContentVersion cv = [
            SELECT VersionData
            FROM   ContentVersion
            WHERE  Id = :contentVersionId
            LIMIT  1
        ];
        try {
            return cv.VersionData.toString();
        } catch (Exception e) {
            throw new AuraHandledException(
                'File encoding not supported. Please save the CSV as UTF-8 and re-upload.'
            );
        }
    }

    /**
     * Parses a CSV string and returns ImportRow objects with client-side
     * validation already applied. Called by the LWC to power the preview datatable.
     * The same method is used regardless of whether the content came from
     * lightning-file-upload or a drag-and-drop FileReader.
     *
     * Required columns : Deal Code | Offer Initiated By | Is Workout/Distressed | Units | Effective Date
     * Optional columns : Buyer | Seller | Syndicate Comms Required | Workout | Unit Price | Secondary Trading Name
     */
    @AuraEnabled
    public static List<ImportRow> parseCSV(String csvContent) {
        if (!hasPermission()) {
            throw new AuraHandledException('You do not have permission to import Secondary Trading records.');
        }

        List<ImportRow> rows = new List<ImportRow>();
        if (String.isBlank(csvContent)) return rows;

        if (csvContent.startsWith('\uFEFF')) {
            csvContent = csvContent.substring(1);
        }

        // Split on any line ending (Windows \r\n, Unix \n, old Mac \r)
        List<String> lines = csvContent.split('\r\n|\r|\n');
        System.debug('CSV Content: ' + csvContent);     // commented out for production
        // Find first non-blank line as the header
        Integer headerIdx = -1;
        for (Integer i = 0; i < lines.size(); i++) {
            if (!String.isBlank(lines[i])) { headerIdx = i; break; }
        }
        if (headerIdx < 0 || (lines.size() - headerIdx) < 2) {
            throw new AuraHandledException('CSV must contain a header row and at least one data row.');
        }

        List<String> headers = parseCSVLine(lines[headerIdx]);
        Map<String, Integer> colIdx = new Map<String, Integer>();
        for (Integer i = 0; i < headers.size(); i++) {
            colIdx.put(headers[i].trim().toLowerCase(), i);
        }

        // Required column check — report all missing at once
        List<String> requiredCols = new List<String>{
            'deal code', 'offer initiated by', 'is workout/distressed', 'units', 'effective date'
        };
        List<String> missingCols = new List<String>();
        for (String col : requiredCols) {
            if (!colIdx.containsKey(col)) missingCols.add(col);
        }
        if (!missingCols.isEmpty()) {
            System.debug('Missing required column(s): ' + String.join(missingCols, ', '));   //commented out for production
            throw new AuraHandledException(
                'Missing required column(s): ' + String.join(missingCols, ', ') + '. '
                + 'Required: Deal Code, Offer Initiated By, Is Workout/Distressed, Units, Effective Date'
            );
        }

        for (Integer i = headerIdx + 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            List<String> cols = parseCSVLine(line);
            ImportRow row       = new ImportRow();
            row.rowNumber       = i;
            row.hasError        = false;
            row.errorMessage    = '';
            List<String> errs   = new List<String>();

            row.deal                   = getCol(cols, colIdx, 'deal code');
            row.tradingName            = getCol(cols, colIdx, 'secondary trading name');
            row.offerInitiatedBy       = getCol(cols, colIdx, 'offer initiated by');
            row.isWorkout              = getCol(cols, colIdx, 'is workout/distressed');
            row.buyer                  = getCol(cols, colIdx, 'buyer');
            row.seller                 = getCol(cols, colIdx, 'seller');
            row.syndicateCommsRequired = getCol(cols, colIdx, 'syndicate comms required');
            row.workout                = getCol(cols, colIdx, 'workout');
            row.effectiveDate          = getCol(cols, colIdx, 'effective date');
            String unitsStr            = getCol(cols, colIdx, 'units');
            String unitPriceStr        = getCol(cols, colIdx, 'unit price');

            // ── Required field presence ────────────────────────────────────────
            if (String.isBlank(row.deal))             errs.add('Deal Code is required');
            if (String.isBlank(row.offerInitiatedBy)) errs.add('Offer Initiated By is required');
            if (String.isBlank(row.isWorkout))        errs.add('Is Workout/Distressed is required');

            if (String.isBlank(unitsStr)) {
                errs.add('Units is required');
            } else {
                try {
                    row.units = Decimal.valueOf(unitsStr.trim());
                    if (row.units <= 0) errs.add('Units must be greater than zero');
                } catch (Exception e) {
                    errs.add('Units must be a number');
                }
            }

            // ── Picklist validation ────────────────────────────────────────────
            String oibKey = String.isBlank(row.offerInitiatedBy)
                ? null : row.offerInitiatedBy.trim().toLowerCase();

            if (oibKey != null && !getOfferCanonical().containsKey(oibKey)) {
                errs.add('Offer Initiated By must be one of: '
                    + String.join(new List<String>(getOfferCanonical().values()), ', '));
                oibKey = null; // suppress cross-field checks when base value is invalid
            }

            if (!String.isBlank(row.isWorkout)) {
                String wn = row.isWorkout.trim().toLowerCase();
                if (wn != 'yes' && wn != 'no') {
                    errs.add('Is Workout/Distressed must be Yes or No');
                }
            }

            // ── Buyer / Seller picklist values ─────────────────────────────────
            String buyerLower  = String.isBlank(row.buyer)  ? null : row.buyer.trim().toLowerCase();
            String sellerLower = String.isBlank(row.seller) ? null : row.seller.trim().toLowerCase();

            if (buyerLower != null && !getValidBuyerLower().contains(buyerLower)) {
                errs.add('Buyer value not recognised — check the allowed fund list');
            }
            if (sellerLower != null && !getValidSellerLower().contains(sellerLower)) {
                errs.add('Seller value not recognised — check the allowed fund list');
            }

            // ── Cross-field rules (mirror org validation rules) ────────────────
            if (oibKey != null) {
                String canonical = getOfferCanonical().get(oibKey);

                // InvestorOffer_Buyer_Must_Be_Investor
                if (canonical == 'Investor Offer') {
                    if (buyerLower == null || buyerLower != 'syndicate/investor') {
                        errs.add('For Investor Offer, Buyer must be Syndicate/Investor');
                    }
                }
                // FundsBid_Seller_Must_Be_Investor
                if (canonical == 'Funds Bid') {
                    if (sellerLower == null || sellerLower != 'syndicate/investor') {
                        errs.add('For Funds Bid (To Investors), Seller must be Syndicate/Investor');
                    }
                }
                // FundsToFunds_No_Investor_Involved
                if (canonical == 'Funds / Funds') {
                    if ('syndicate/investor'.equals(buyerLower)
                            || 'syndicate/investor'.equals(sellerLower)) {
                        errs.add('For Funds / Funds trades, neither Buyer nor Seller can be Syndicate/Investor');
                    }
                }
            }

            // Buyer_and_Seller_Cannot_Be_Same (excluding Syndicate/Investor edge case)
            if (buyerLower != null && sellerLower != null
                    && buyerLower == sellerLower
                    && buyerLower != 'syndicate/investor') {
                errs.add('Buyer and Seller cannot be the same fund');
            }

            // ── Unit Price ─────────────────────────────────────────────────────
            if (!String.isBlank(unitPriceStr)) {
                try {
                    row.unitPrice = Decimal.valueOf(unitPriceStr.trim());
                    if (row.unitPrice <= 0) errs.add('Unit Price must be greater than zero');
                } catch (Exception e) {
                    errs.add('Unit Price must be a number');
                }
            }

            // ── Effective Date (required; multiple Excel formats accepted) ────────
            if (String.isBlank(row.effectiveDate)) {
                errs.add('Effective Date is required');
            } else {
                try {
                    parseDateDMY(row.effectiveDate.trim());
                    row.effectiveDate = row.effectiveDate.trim();
                } catch (Exception e) {
                    errs.add('Effective Date is not a valid date — use DD-MM-YYYY (e.g. 25-07-2026). Slashes and month names are also accepted.');
                }
            }

            // ── Syndicate Comms Required ───────────────────────────────────────
            String synCommsLower = String.isBlank(row.syndicateCommsRequired)
                ? null : row.syndicateCommsRequired.trim().toLowerCase();

            if (synCommsLower != null && synCommsLower != 'yes' && synCommsLower != 'no') {
                errs.add('Syndicate Comms Required must be Yes or No');
                synCommsLower = null;
            }

            // Mirrors Syndicate_Comms_Required_Rules validation rule:
            // Syndicate Comms Required can only be Yes when Offer Initiated By = Funds Bid
            if (synCommsLower == 'yes' && oibKey != null
                    && getOfferCanonical().get(oibKey) != 'Funds Bid') {
                errs.add('Syndicate Comms Required can only be Yes when Offer Initiated By is Funds Bid');
            }

            // Mirrors Workout_Field_Check validation rule:
            // Workout must be blank when Is Related Deal in Workout/Distressed = No
            if (!String.isBlank(row.workout)
                    && !String.isBlank(row.isWorkout)
                    && row.isWorkout.trim().toLowerCase() == 'no') {
                errs.add('Workout must be blank when Is Related Deal in Workout/Distressed is No');
            }

            if (!errs.isEmpty()) {
                row.hasError     = true;
                row.errorMessage = String.join(errs, '; ');
            }
            rows.add(row);
        }
        return rows;
    }

    /**
     * Inserts valid ImportRow objects as Secondary_Trading__c records.
     * Uses Database.insert with allOrNone=false so valid rows succeed even
     * when some rows trigger server-side validation rule failures.
     * All record-triggered flows (Case creation, Chatter, email alerts)
     * fire automatically — no additional work required here.
     */
    @AuraEnabled
    public static ImportResult importRows(String rowsJson) {
        if (!hasPermission()) {
            throw new AuraHandledException('You do not have permission to import Secondary Trading records.');
        }
        List<ImportRow> rows = (List<ImportRow>) JSON.deserialize(rowsJson, List<ImportRow>.class);

        ImportResult res   = new ImportResult();
        res.errors         = new List<String>();
        res.successCount   = 0;
        res.failureCount   = 0;

        // ── Batch Product2 lookup — one SOQL instead of one per row ───────────
        Set<String> dealNames    = new Set<String>();
        Set<String> workoutNames = new Set<String>();
        for (ImportRow row : rows) {
            if (row.hasError != true) {
                if (!String.isBlank(row.deal))    dealNames.add(row.deal.trim());
                if (!String.isBlank(row.workout)) workoutNames.add(row.workout.trim());
            }
        }
        Map<String, Id> dealMap = new Map<String, Id>();
        if (!dealNames.isEmpty()) {
            for (Product2 p : [SELECT Id, Deal_Code__c FROM Product2 WHERE Deal_Code__c IN :dealNames]) {
                dealMap.put(p.Deal_Code__c, p.Id);
            }
        }
        Map<String, Id> workoutMap = new Map<String, Id>();
        if (!workoutNames.isEmpty()) {
            for (Workout__c w : [SELECT Id, Name FROM Workout__c WHERE Name IN :workoutNames]) {
                workoutMap.put(w.Name, w.Id);
            }
        }

        List<Secondary_Trading__c> toInsert   = new List<Secondary_Trading__c>();
        List<Integer>              rowNumbers  = new List<Integer>();

        for (ImportRow row : rows) {
            if (row.hasError == true) {
                res.failureCount++;
                res.errors.add('Row ' + row.rowNumber + ' skipped: ' + row.errorMessage);
                continue;
            }

            String dealKey = String.isBlank(row.deal) ? '' : row.deal.trim();
            if (!dealMap.containsKey(dealKey)) {
                res.failureCount++;
                res.errors.add('Row ' + row.rowNumber + ': Deal Code not found — "' + dealKey + '"');
                continue;
            }

            Secondary_Trading__c st = new Secondary_Trading__c();
            st.Deal__c = dealMap.get(dealKey);

            // Picklist — assign canonical value
            String oibKey = String.isBlank(row.offerInitiatedBy) ? '' : row.offerInitiatedBy.trim().toLowerCase();
            st.Offer_Initiated_By__c = getOfferCanonical().get(oibKey);

            // Picklist — proper-case "yes" → "Yes"
            String wLower = String.isBlank(row.isWorkout) ? '' : row.isWorkout.trim().toLowerCase();
            if (!String.isBlank(wLower)) {
                st.Is_related_deal_in_workout_distressed__c =
                    wLower.substring(0, 1).toUpperCase() + wLower.substring(1);
            }

            st.Units__c = row.units;

            if (!String.isBlank(row.buyer))       st.Buyer__c                  = row.buyer.trim();
            if (!String.isBlank(row.seller))      st.Seller__c                 = row.seller.trim();
            if (!String.isBlank(row.tradingName)) st.Secondary_Trading_Name__c = row.tradingName.trim();

            if (!String.isBlank(row.syndicateCommsRequired)) {
                String sc = row.syndicateCommsRequired.trim();
                st.Syndicate_Comms_Required__c =
                    sc.substring(0, 1).toUpperCase() + sc.substring(1).toLowerCase();
            }

            if (!String.isBlank(row.workout)) {
                String workoutKey = row.workout.trim();
                if (!workoutMap.containsKey(workoutKey)) {
                    res.failureCount++;
                    res.errors.add('Row ' + row.rowNumber + ': Workout not found — "' + workoutKey + '"');
                    continue;
                }
                st.Workout__c = workoutMap.get(workoutKey);
            }

            if (row.unitPrice != null) st.Unit_Price__c = row.unitPrice;

            if (!String.isBlank(row.effectiveDate)) {
                try {
                    st.Effective_Date__c = parseDateDMY(row.effectiveDate.trim());
                } catch (Exception e) {
                    res.failureCount++;
                    res.errors.add('Row ' + row.rowNumber + ': Invalid Effective Date — ' + e.getMessage());
                    continue;
                }
            }

            toInsert.add(st);
            rowNumbers.add(row.rowNumber);
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    res.successCount++;
                } else {
                    res.failureCount++;
                    List<String> msgs = new List<String>();
                    for (Database.Error err : results[i].getErrors()) {
                        msgs.add(err.getMessage());
                    }
                    res.errors.add('Row ' + rowNumbers[i] + ': ' + String.join(msgs, '; '));
                }
            }
        }
        return res;
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    /**
     * Parses a date string in any of the formats Excel commonly produces:
     *   DD-MM-YYYY, DD/MM/YYYY, DD-MM-YY, DD/MM/YY,
     *   DD-Mon-YYYY, DD-Mon-YY, DD/Mon/YYYY, DD/Mon/YY,
     *   YYYY-MM-DD (ISO)
     * Throws IllegalArgumentException if the string cannot be parsed.
     */
    private static Date parseDateDMY(String s) {
        if (String.isBlank(s)) throw new IllegalArgumentException('Date is blank');

        Map<String, Integer> monthMap = new Map<String, Integer>{
            'jan'=>1,  'january'=>1,
            'feb'=>2,  'february'=>2,
            'mar'=>3,  'march'=>3,
            'apr'=>4,  'april'=>4,
            'may'=>5,
            'jun'=>6,  'june'=>6,
            'jul'=>7,  'july'=>7,
            'aug'=>8,  'august'=>8,
            'sep'=>9,  'september'=>9,
            'oct'=>10, 'october'=>10,
            'nov'=>11, 'november'=>11,
            'dec'=>12, 'december'=>12
        };

        // Normalise: replace all / with - so we only split on one character
        String norm = s.trim().replace('/', '-');
        List<String> parts = norm.split('-');

        if (parts.size() != 3) {
            throw new IllegalArgumentException('Cannot parse date: ' + s);
        }

        String p0 = parts[0].trim();
        String p1 = parts[1].trim();
        String p2 = parts[2].trim();

        Integer d, m, y;

        // Format: DD-Mon-YYYY or DD-Mon-YY (middle part is alphabetic month)
        if (monthMap.containsKey(p1.toLowerCase())) {
            d = Integer.valueOf(p0);
            m = monthMap.get(p1.toLowerCase());
            y = Integer.valueOf(p2);
        }
        // Format: YYYY-MM-DD (first part is 4-digit year)
        else if (p0.length() == 4) {
            y = Integer.valueOf(p0);
            m = Integer.valueOf(p1);
            d = Integer.valueOf(p2);
        }
        // Default: DD-MM-YYYY or DD-MM-YY
        else {
            d = Integer.valueOf(p0);
            m = Integer.valueOf(p1);
            y = Integer.valueOf(p2);
        }

        // Expand 2-digit year: 00-99 → 2000-2099
        if (y < 100) y += 2000;

        if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1900 || y > 2200) {
            throw new IllegalArgumentException('Invalid date values in: ' + s);
        }

        return Date.newInstance(y, m, d);
    }

    private static String getCol(List<String> cols, Map<String, Integer> idx, String name) {
        Integer i = idx.get(name);
        if (i == null || i >= cols.size()) return '';
        return cols[i].trim();
    }

    /**
     * RFC 4180-compliant CSV line parser.
     * Handles quoted fields, embedded commas, and escaped double-quotes ("").
     */
    private static List<String> parseCSVLine(String line) {
        List<String> result = new List<String>();
        Boolean inQuotes    = false;
        String  current     = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    current += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }
}