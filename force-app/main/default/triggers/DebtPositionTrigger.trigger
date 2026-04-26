/**
 * DebtPositionTrigger
 * Single-responsibility trigger — delegates all logic to DebtPositionTriggerHandler.
 * No business logic here. One trigger per object.
 */
trigger DebtPositionTrigger on Debt_Position__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new DebtPositionTriggerHandler().run();
}
