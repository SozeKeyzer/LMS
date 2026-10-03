/**
 * RateIndexFixingTrigger
 * Single-responsibility trigger — delegates all logic to RateIndexFixingHandler.
 * No business logic here. One trigger per object.
 */
trigger RateIndexFixingTrigger on Rate_Index_Fixing__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new RateIndexFixingHandler().run();
}