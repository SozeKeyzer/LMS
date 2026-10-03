/**
 * ElectionTrigger
 * Delegates all logic to ElectionHandler. No business logic here.
 */
trigger ElectionTrigger on Election__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    new ElectionHandler().run();
}