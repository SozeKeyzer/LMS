/**
 * RateApplicationEventTrigger
 * Single-responsibility trigger — delegates all logic to RateApplicationEventHandler.
 * No business logic here. One trigger per object.
 */
trigger RateApplicationEventTrigger on Rate_Application_Event__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new RateApplicationEventHandler().run();
}