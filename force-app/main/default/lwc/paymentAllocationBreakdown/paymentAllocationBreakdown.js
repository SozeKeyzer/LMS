import { LightningElement, api, track } from 'lwc';

export default class PaymentAllocationBreakdown extends LightningElement {
    @api recordId; // Payment_Transaction__c Id
    @track allocations = [];
    @track totalAmount = 0;
    @track waterfallRule = '';
    @track unallocatedAmount = 0;

    get hasUnallocated() { return this.unallocatedAmount > 0; }

    connectedCallback() {
        // Wire to getAllocationsForTransaction Apex in full impl
    }
}