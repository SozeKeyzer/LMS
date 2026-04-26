/**
 * FinancialInstrumentTrigger
 * Single-responsibility trigger — delegates all logic to FinancialInstrumentTriggerHandler.
 * No business logic here. One trigger per object.
 */
trigger FinancialInstrumentTrigger on Financial_Instrument__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new FinancialInstrumentTriggerHandler().run();
}
