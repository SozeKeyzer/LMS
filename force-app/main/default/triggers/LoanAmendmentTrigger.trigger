/**
 * LoanAmendmentTrigger
 * Single-responsibility trigger — delegates all logic to LoanAmendmentHandler.
 * No business logic here. One trigger per object.
 */
trigger LoanAmendmentTrigger on Loan_Amendment__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    new LoanAmendmentHandler().run();
}