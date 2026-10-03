/**
 * PaymentAdjustmentTrigger
 * Single-responsibility trigger — delegates all logic to PaymentAdjustmentHandler.
 * No business logic here. One trigger per object.
 */
trigger PaymentAdjustmentTrigger on Payment_Adjustment__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new PaymentAdjustmentHandler().run();
}