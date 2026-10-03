import { LightningElement, api, track } from 'lwc';

export default class ReconciliationDashboardTile extends LightningElement {
    @api recordId; // Debt_Position__c Id
    @track accruedTotal = 0;
    @track scheduledTotal = 0;
    @track cashReceived = 0;
    @track divergenceAmount = 0;

    get isDiverged() { return Math.abs(this.divergenceAmount) > 0.01; }

    connectedCallback() {
        // Wire to getReconciliationData Apex in full impl
    }
}