/**
 * FeeStructuresTrigger
 * Single-responsibility trigger — delegates all logic to FeeStructuresTriggerHandler.
 * No business logic here. One trigger per object.
 */
trigger FeeStructuresTrigger on Fee_Structures__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new FeeStructuresTriggerHandler().run();
}
