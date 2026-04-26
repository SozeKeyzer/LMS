/**
 * AmortisationRulesTrigger
 * Single-responsibility trigger — delegates all logic to AmortisationRulesTriggerHandler.
 * No business logic here. One trigger per object.
 */
trigger AmortisationRulesTrigger on Amortisation_Rules__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new AmortisationRulesTriggerHandler().run();
}
