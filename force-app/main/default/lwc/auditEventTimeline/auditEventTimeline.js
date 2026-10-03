import { LightningElement, api, track } from 'lwc';
import getAuditEventsByCorrelationId from '@salesforce/apex/AuditEventController.getAuditEventsByCorrelationId';

export default class AuditEventTimeline extends LightningElement {
    @api recordId;
    @track correlationId = '';
    @track events = [];
    @track isLoading = false;
    @track error;

    handleCorrelationChange(evt) {
        this.correlationId = evt.target.value;
    }

    handleSearch() {
        if (!this.correlationId) return;
        this.isLoading = true;
        this.error = undefined;
        this.events = [];
        getAuditEventsByCorrelationId({ correlationId: this.correlationId })
            .then(data => {
                this.events = data;
                this.isLoading = false;
            })
            .catch(err => {
                this.error = err.body?.message || 'Unexpected error';
                this.isLoading = false;
            });
    }

    get hasEvents() {
        return this.events && this.events.length > 0;
    }
}