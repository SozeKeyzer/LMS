/**
 * PaymentTransactionTrigger
 * Single-responsibility trigger — delegates all logic to PaymentTransactionHandler.
 * No business logic here. One trigger per object.
 */
trigger PaymentTransactionTrigger on Payment_Transaction__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new PaymentTransactionHandler().run();
}