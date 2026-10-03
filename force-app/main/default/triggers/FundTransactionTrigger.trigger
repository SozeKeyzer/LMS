trigger FundTransactionTrigger on Fund_Transaction__c (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FundTransactionTriggerHandler.setOwner(Trigger.new);
    }
}
