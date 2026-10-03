/**
 * ProjectionTrigger
 * Single-responsibility trigger — delegates all logic to ProjectionHandler.
 * No business logic here. One trigger per object.
 */
trigger ProjectionTrigger on Projection__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new ProjectionHandler().run();
}