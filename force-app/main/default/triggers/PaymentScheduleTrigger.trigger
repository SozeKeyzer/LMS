/**
 * PaymentScheduleTrigger
 * Single-responsibility trigger — delegates all logic to PaymentScheduleHandler.
 * No business logic here. One trigger per object.
 */
trigger PaymentScheduleTrigger on Payment_Schedule__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new PaymentScheduleHandler().run();
}