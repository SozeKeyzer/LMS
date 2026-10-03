/**
 * PrepaymentEventTrigger
 * Delegates all logic to PrepaymentEventHandler. No business logic here.
 */
trigger PrepaymentEventTrigger on Prepayment_Event__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    new PrepaymentEventHandler().run();
}