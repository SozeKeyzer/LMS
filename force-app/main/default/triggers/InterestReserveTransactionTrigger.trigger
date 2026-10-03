/**
 * InterestReserveTransactionTrigger
 * Delegates all logic to InterestReserveTransactionHandler.
 * Key responsibility: afterInsert updates Current_Reserve_Balance on parent.
 */
trigger InterestReserveTransactionTrigger on Interest_Reserve_Transaction__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    new InterestReserveTransactionHandler().run();
}
