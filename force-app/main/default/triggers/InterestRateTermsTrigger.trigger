/**
 * InterestRateTermsTrigger
 * Single-responsibility trigger — delegates all logic to InterestRateTermsTriggerHandler.
 * No business logic here. One trigger per object.
 */
trigger InterestRateTermsTrigger on Interest_Rate_Terms__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new InterestRateTermsTriggerHandler().run();
}
