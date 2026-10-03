/**
 * PaymentAllocationTrigger
 * Single-responsibility trigger — delegates all logic to PaymentAllocationHandler.
 * No business logic here. One trigger per object.
 */
trigger PaymentAllocationTrigger on Payment_Allocation__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new PaymentAllocationHandler().run();
}