/**
 * AccrualDailyTrigger
 * Single-responsibility trigger — delegates all logic to AccrualDailyHandler.
 * No business logic here. One trigger per object.
 */
trigger AccrualDailyTrigger on Accrual_Daily__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new AccrualDailyHandler().run();
}