import { LightningElement, api, track } from 'lwc';

export default class ProvenancePopover extends LightningElement {
    @api fieldLabel;
    @api value;
    @api calcName;
    @api version;
    @api runName;
    @api runAt;
    @api runBy;
    @api inputsSummary;
    @api formulaSummary;
    @api overrideStatus;
    @api runId;
    @track isOpen = false;

    togglePopover() { this.isOpen = !this.isOpen; }

    openRun() {
        if (this.runId) {
            // eslint-disable-next-line no-restricted-globals
            window.location.href = `/lightning/r/Calculation_Run__c/${this.runId}/view`;
        }
        this.isOpen = false;
    }

    requestOverride() {
        this.dispatchEvent(new CustomEvent('requestoverride', {
            detail: { runId: this.runId, fieldLabel: this.fieldLabel, value: this.value }
        }));
        this.isOpen = false;
    }
}
