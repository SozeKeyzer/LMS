import { LightningElement, api, track } from 'lwc';

export default class RatesAndAccrualHistory extends LightningElement {
    @api recordId; // Debt_Position__c Id
    @track rateSegments = [];

    connectedCallback() {
        // Wire to getRateHistory Apex method in full impl
    }
}