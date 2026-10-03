public with sharing class FundTransactionTriggerHandler {

    public static void setOwner(List<Fund_Transaction__c> records) {
        for (Fund_Transaction__c r : records) {
            if (r.BDM__c != null) {
                r.OwnerId = r.BDM__c;
            }
        }
    }
}
