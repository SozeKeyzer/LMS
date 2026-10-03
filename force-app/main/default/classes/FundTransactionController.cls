public with sharing class FundTransactionController {

    public class CSVImportRow {
        @AuraEnabled public String  transactionDate      { get; set; }
        @AuraEnabled public String  fundName             { get; set; }
        @AuraEnabled public String  entityId             { get; set; }
        @AuraEnabled public String  transactionType      { get; set; }
        @AuraEnabled public Decimal amount               { get; set; }
        @AuraEnabled public String  bdmUsername          { get; set; }
        @AuraEnabled public String  switchedFromFundName { get; set; }
        @AuraEnabled public String  moneyReceivedBoolean  { get; set; }
        @AuraEnabled public String  moneyReceivedOn       { get; set; }
        @AuraEnabled public String  switchCompleted      { get; set; }
        @AuraEnabled public String  comment              { get; set; }
        @AuraEnabled public String  fiName               { get; set; }
        @AuraEnabled public String  warehouseName        { get; set; }
        @AuraEnabled public Integer rowIndex             { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTransactions(
        List<String> fundIds,
        List<String> txTypes,
        List<String> months,
        Boolean intrafundOnly,
        Integer pageSize,
        Integer offset
    ) {
        Id userId = UserInfo.getUserId();
        Boolean isFullAccess     = FeatureManagement.checkPermission('Full_Transaction_Access');
        Boolean canSeeRestricted = FeatureManagement.checkPermission('View_Restricted_Transactions');

        String q = 'SELECT Id, Name, Transaction_Date__c, Fund__r.Name, Fund__c,'
                 + ' Financial_Instrument__r.Name, Financial_Instrument__c,'
                 + ' Warehouse_Note__r.Name, Warehouse_Note__c,'
                 + ' Investment_Vehicle_Type__c,'
                 + ' Investor_Entity__r.Name, Entity_Used__c,'
                 + ' Investor_Entity_ID__c, Investor_Entity_Name__c,'
                 + ' Transaction_Type__c, Amount__c, BDM__r.Name, BDM__c, Month__c,'
                 + ' Switched_From__r.Name, Switched_From__c, Intrafund__c,'
                 + ' Restricted_Entity__c, Switch_Completed__c,'
                 + ' Money_Received_On__c, Money_Received__c,'
                 + ' Primary_Contact_Name__c, Primary_Contact_Email__c, Comment__c'
                 + ' FROM Fund_Transaction__c WHERE Id != null';

        if (!isFullAccess)                             q += ' AND BDM__c = \'' + userId + '\'';
        if (!canSeeRestricted)                         q += ' AND Restricted_Entity__c = false';
        if (fundIds != null && !fundIds.isEmpty())     q += ' AND Fund__c IN :fundIds';
        if (txTypes != null && !txTypes.isEmpty())     q += ' AND Transaction_Type__c IN :txTypes';
        if (months  != null && !months.isEmpty())      q += ' AND Month__c IN :months';
        if (intrafundOnly == true)                     q += ' AND Intrafund__c = true';

        String countQ = 'SELECT COUNT() FROM Fund_Transaction__c WHERE Id != null';
        if (!isFullAccess)                             countQ += ' AND BDM__c = \'' + userId + '\'';
        if (!canSeeRestricted)                         countQ += ' AND Restricted_Entity__c = false';
        if (fundIds != null && !fundIds.isEmpty())     countQ += ' AND Fund__c IN :fundIds';
        if (txTypes != null && !txTypes.isEmpty())     countQ += ' AND Transaction_Type__c IN :txTypes';
        if (months  != null && !months.isEmpty())      countQ += ' AND Month__c IN :months';
        if (intrafundOnly == true)                     countQ += ' AND Intrafund__c = true';

        q += ' ORDER BY Transaction_Date__c DESC LIMIT ' + pageSize + ' OFFSET ' + offset;

        List<Fund_Transaction__c> records = Database.query(q);
        Integer total = Database.countQuery(countQ);

        return new Map<String, Object>{
            'records' => records,
            'total'   => total
        };
    }

    @AuraEnabled
    public static Fund_Transaction__c getTransactionById(String recordId) {
        return [
            SELECT Id, Transaction_Date__c,
                   Investment_Vehicle_Type__c,
                   Fund__c, Fund__r.Name,
                   Financial_Instrument__c, Financial_Instrument__r.Name,
                   Warehouse_Note__c, Warehouse_Note__r.Name,
                   Investor_Entity__c,
                   Investor_Entity_ID__c, Investor_Entity_Name__c,
                   Transaction_Type__c, Amount__c, BDM__c,
                   Switched_From__c, Switched_From__r.Name,
                   Switch_Completed__c,
                   Money_Received_On__c, Money_Received__c,
                   Comment__c
            FROM Fund_Transaction__c
            WHERE Id = :recordId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static List<Financial_Instrument__c> searchFinancialInstruments(String searchTerm) {
        String likeVal = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name FROM Financial_Instrument__c
            WHERE Name LIKE :likeVal
            WITH USER_MODE
            ORDER BY Name
            LIMIT 10
        ];
    }

    @AuraEnabled
    public static List<Warehouse_Note__c> searchWarehouseNotes(String searchTerm) {
        String likeVal = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name FROM Warehouse_Note__c
            WHERE Name LIKE :likeVal
            WITH USER_MODE
            ORDER BY Name
            LIMIT 10
        ];
    }

    @AuraEnabled
    public static Map<String, Object> saveBulk(List<Fund_Transaction__c> records) {
        Database.SaveResult[] results = Database.insert(records, false);
        Integer saved = 0;
        List<String> insertErrors = new List<String>();

        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                saved++;
            } else {
                insertErrors.add(sr.getErrors()[0].getMessage());
            }
        }

        return new Map<String, Object>{
            'saved'  => saved,
            'errors' => insertErrors
        };
    }

    @AuraEnabled
    public static Map<String, Object> saveTransaction(Fund_Transaction__c record) {
        try {
            upsert record;
            return new Map<String, Object>{ 'saved' => true, 'errors' => new List<String>() };
        } catch (DmlException e) {
            return new Map<String, Object>{
                'saved'  => false,
                'errors' => new List<String>{ e.getDmlMessage(0) }
            };
        }
    }

    @AuraEnabled
    public static Map<String, Object> importCSVRaw(
        List<CSVImportRow> rows,
        String sourceFileName
    ) {
        if (!FeatureManagement.checkPermission('Fund_Transaction_Importer')) {
            throw new AuraHandledException('You do not have permission to import transactions.');
        }

        Set<String> fundNames    = new Set<String>();
        Set<String> entityIds    = new Set<String>();
        Set<String> bdmUsernames = new Set<String>();
        Set<String> fiNames      = new Set<String>();
        Set<String> wnNames      = new Set<String>();

        for (CSVImportRow r : rows) {
            if (String.isNotBlank(r.fundName))             fundNames.add(r.fundName);
            if (String.isNotBlank(r.switchedFromFundName)) fundNames.add(r.switchedFromFundName);
            if (String.isNotBlank(r.entityId))             entityIds.add(r.entityId);
            if (String.isNotBlank(r.bdmUsername))          bdmUsernames.add(r.bdmUsername);
            if (String.isNotBlank(r.fiName))               fiNames.add(r.fiName);
            if (String.isNotBlank(r.warehouseName))        wnNames.add(r.warehouseName);
        }

        Map<String, Integer> fundNameCount = new Map<String, Integer>();
        for (Funds__c f : [SELECT Id, Name FROM Funds__c WHERE Name IN :fundNames WITH USER_MODE]) {
            fundNameCount.put(f.Name, (fundNameCount.containsKey(f.Name) ? fundNameCount.get(f.Name) : 0) + 1);
        }
        Set<String> ambiguousFundNames = new Set<String>();
        Map<String, Id> fundNameToId   = new Map<String, Id>();
        for (Funds__c f : [SELECT Id, Name FROM Funds__c WHERE Name IN :fundNames WITH USER_MODE ORDER BY CreatedDate ASC]) {
            if (fundNameCount.get(f.Name) > 1) {
                ambiguousFundNames.add(f.Name);
            } else {
                fundNameToId.put(f.Name, f.Id);
            }
        }

        Map<String, Id>     entityIdToAccountId = new Map<String, Id>();
        Map<String, String> entityIdToName      = new Map<String, String>();
        for (Account a : [SELECT Id, Name, Investor_Entity_ID__c FROM Account
                          WHERE Investor_Entity_ID__c IN :entityIds WITH USER_MODE]) {
            entityIdToAccountId.put(a.Investor_Entity_ID__c, a.Id);
            entityIdToName.put(a.Investor_Entity_ID__c, a.Name);
        }

        Map<String, Id> usernameToUserId = new Map<String, Id>();
        for (User u : [SELECT Id, Username FROM User
                       WHERE Username IN :bdmUsernames AND IsActive = true]) {
            usernameToUserId.put(u.Username, u.Id);
        }

        Map<String, Id> fiNameToId = new Map<String, Id>();
        if (!fiNames.isEmpty()) {
            for (Financial_Instrument__c fi : [SELECT Id, Name FROM Financial_Instrument__c WHERE Name IN :fiNames WITH USER_MODE]) {
                fiNameToId.put(fi.Name, fi.Id);
            }
        }

        Map<String, Id> wnNameToId = new Map<String, Id>();
        if (!wnNames.isEmpty()) {
            for (Warehouse_Note__c wn : [SELECT Id, Name FROM Warehouse_Note__c WHERE Name IN :wnNames WITH USER_MODE]) {
                wnNameToId.put(wn.Name, wn.Id);
            }
        }

        List<Fund_Transaction__c>  records          = new List<Fund_Transaction__c>();
        List<Integer>              recordRowIndices  = new List<Integer>();
        List<Map<String, Object>>  resolutionErrors = new List<Map<String, Object>>();

        for (CSVImportRow r : rows) {
            List<String> rowErrors = new List<String>();

            Id fundId       = String.isNotBlank(r.fundName)             ? fundNameToId.get(r.fundName)              : null;
            Id fiId         = String.isNotBlank(r.fiName)               ? fiNameToId.get(r.fiName)                  : null;
            Id warehouseId  = String.isNotBlank(r.warehouseName)        ? wnNameToId.get(r.warehouseName)           : null;
            Id accountId    = entityIdToAccountId.get(r.entityId);
            Id bdmUserId    = String.isNotBlank(r.bdmUsername)          ? usernameToUserId.get(r.bdmUsername)       : null;
            Id switchFromId = String.isNotBlank(r.switchedFromFundName) ? fundNameToId.get(r.switchedFromFundName)  : null;

            String vehicleType;
            if      (String.isNotBlank(r.fundName))      vehicleType = 'Fund';
            else if (String.isNotBlank(r.fiName))        vehicleType = 'Financial Instrument';
            else if (String.isNotBlank(r.warehouseName)) vehicleType = 'Warehouse Note';
            else {
                rowErrors.add('At least one vehicle must be specified: Fund_Name, Financial_Instrument_Name, or Warehouse_Note_Name');
                vehicleType = 'Fund';
            }

            if (String.isNotBlank(r.fundName)) {
                if (ambiguousFundNames.contains(r.fundName)) rowErrors.add('Ambiguous fund name (multiple matches): ' + r.fundName + '. Use a unique name.');
                else if (fundId == null)                     rowErrors.add('Fund not found: ' + r.fundName);
            }
            if (String.isNotBlank(r.fiName) && fiId == null)              rowErrors.add('Financial Instrument not found: ' + r.fiName);
            if (String.isNotBlank(r.warehouseName) && warehouseId == null) rowErrors.add('Warehouse Note not found: ' + r.warehouseName);

            if (accountId == null) rowErrors.add('Entity not found: ' + r.entityId);
            if (String.isNotBlank(r.bdmUsername) && bdmUserId == null) rowErrors.add('BDM user not found: ' + r.bdmUsername);
            if (String.isNotBlank(r.switchedFromFundName) && ambiguousFundNames.contains(r.switchedFromFundName))
                rowErrors.add('Ambiguous switched-from fund name (multiple matches): ' + r.switchedFromFundName);
            else if (String.isNotBlank(r.switchedFromFundName) && switchFromId == null)
                rowErrors.add('Switched-from fund not found: ' + r.switchedFromFundName);

            if (!rowErrors.isEmpty()) {
                resolutionErrors.add(new Map<String, Object>{
                    'rowIndex' => r.rowIndex,
                    'errors'   => rowErrors
                });
                continue;
            }

            Date txDate;
            Date moneyDate;
            Date switchDate;
            try {
                txDate     = String.isNotBlank(r.transactionDate) ? parseDateDMY(r.transactionDate.trim()) : null;
                moneyDate  = String.isNotBlank(r.moneyReceivedOn) ? parseDateDMY(r.moneyReceivedOn.trim()) : null;
                switchDate = String.isNotBlank(r.switchCompleted) ? parseDateDMY(r.switchCompleted.trim()) : null;
            } catch (Exception e) {
                resolutionErrors.add(new Map<String, Object>{
                    'rowIndex' => r.rowIndex,
                    'errors'   => new List<String>{ e.getMessage() }
                });
                continue;
            }

            records.add(new Fund_Transaction__c(
                Transaction_Date__c         = txDate,
                Investment_Vehicle_Type__c  = vehicleType,
                Fund__c                     = vehicleType == 'Fund'                  ? fundId      : null,
                Financial_Instrument__c     = vehicleType == 'Financial Instrument'  ? fiId        : null,
                Warehouse_Note__c           = vehicleType == 'Warehouse Note'        ? warehouseId : null,
                Investor_Entity__c          = accountId,
                Investor_Entity_ID__c = r.entityId,
                Investor_Entity_Name__c     = entityIdToName.get(r.entityId),
                Transaction_Type__c         = r.transactionType,
                Amount__c                   = r.amount,
                BDM__c                      = bdmUserId,
                Switched_From__c            = switchFromId,
                Money_Received_On__c        = moneyDate,
                Money_Received__c           = String.isNotBlank(r.moneyReceivedBoolean) && 'yes'.equalsIgnoreCase(r.moneyReceivedBoolean.trim()),
                Switch_Completed__c         = switchDate,
                Comment__c                  = String.isNotBlank(r.comment) ? r.comment : null
            ));
            recordRowIndices.add(r.rowIndex);
        }

        Database.SaveResult[] results = Database.insert(records, false);

        FundTransactionAuditLogger.logImport(
            rows.size(),
            records.size(),
            sourceFileName,
            results
        );

        Integer imported = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                imported++;
            } else {
                resolutionErrors.add(new Map<String, Object>{
                    'rowIndex' => recordRowIndices[i],
                    'errors'   => new List<String>{ results[i].getErrors()[0].getMessage() }
                });
            }
        }

        return new Map<String, Object>{
            'imported'         => imported,
            'resolutionErrors' => resolutionErrors
        };
    }

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

        String norm       = s.trim().replace('/', '-');
        List<String> parts = norm.split('-');

        if (parts.size() != 3) throw new IllegalArgumentException('Invalid date format: ' + s + ' — use DD/MM/YYYY, D-Mon-YY or D-Month-YYYY (e.g. 25/07/2026, 25-Jul-26)');

        String p0 = parts[0].trim();
        String p1 = parts[1].trim();
        String p2 = parts[2].trim();

        Integer d, m, y;

        if (monthMap.containsKey(p1.toLowerCase())) {
            d = Integer.valueOf(p0);
            m = monthMap.get(p1.toLowerCase());
            y = Integer.valueOf(p2);
        } else if (p0.length() == 4) {
            y = Integer.valueOf(p0);
            m = Integer.valueOf(p1);
            d = Integer.valueOf(p2);
        } else {
            d = Integer.valueOf(p0);
            m = Integer.valueOf(p1);
            y = Integer.valueOf(p2);
        }

        if (y < 100) y += 2000;

        if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1900 || y > 2200) {
            throw new IllegalArgumentException('Invalid date values: ' + s);
        }

        return Date.newInstance(y, m, d);
    }

    @AuraEnabled(cacheable=true)
    public static List<Funds__c> getFunds() {
        return [SELECT Id, Name FROM Funds__c WITH USER_MODE ORDER BY Name];
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> searchInvestorEntities(String searchTerm) {
        String likeVal = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, Investor_Entity_ID__c
            FROM Account
            WHERE Investor_Entity_ID__c != null
            AND (Name LIKE :likeVal OR Investor_Entity_ID__c LIKE :likeVal)
            WITH USER_MODE
            ORDER BY Name
            LIMIT 20
        ];
    }

    @AuraEnabled
    public static Map<String, Object> getEntityByExternalId(String entityId) {
        if (String.isBlank(entityId)) return null;
        List<Account> accounts = [
            SELECT Id, Name, Investor_Entity_ID__c
            FROM Account
            WHERE Investor_Entity_ID__c = :entityId.trim()
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) return null;
        return new Map<String, Object>{
            'id'       => accounts[0].Id,
            'name'     => accounts[0].Name,
            'entityId' => accounts[0].Investor_Entity_ID__c
        };
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasCustomPermission(String permissionName) {
        return FeatureManagement.checkPermission(permissionName);
    }
}
