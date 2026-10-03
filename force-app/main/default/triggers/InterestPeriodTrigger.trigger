/**
 * InterestPeriodTrigger
 * Single-responsibility trigger — delegates all logic to InterestPeriodHandler.
 * No business logic here. One trigger per object.
 */
trigger InterestPeriodTrigger on Interest_Period__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new InterestPeriodHandler().run();
}