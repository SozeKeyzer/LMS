public with sharing class FundTransactionAuditLogger {

    public static void logImport(
        Integer rowsInFile,
        Integer rowsToInsert,
        String  sourceFileName,
        Database.SaveResult[] results
    ) {
        Integer imported = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) imported++;
        }

        Import_Audit_Log__c log = new Import_Audit_Log__c(
            Import_DateTime__c  = System.now(),
            Imported_By__c      = UserInfo.getUserId(),
            Source_File_Name__c = sourceFileName,
            Rows_In_File__c     = rowsInFile,
            Rows_Imported__c    = imported
        );

        insert log;
    }
}
