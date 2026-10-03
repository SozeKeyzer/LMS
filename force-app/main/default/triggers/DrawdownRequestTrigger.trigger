/**
 * DrawdownRequestTrigger
 * Delegates all logic to DrawdownRequestHandler. No business logic here.
 */
trigger DrawdownRequestTrigger on Drawdown_Request__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    new DrawdownRequestHandler().run();
}