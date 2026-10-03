import { LightningElement, api, track } from 'lwc';
import preview from '@salesforce/apex/CascadePreviewController.preview';
import commitCascade from '@salesforce/apex/CascadePreviewController.commitCascade';

export default class CascadePreviewPanel extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api fieldApiName;
    @api proposedValue;
    @api originalValue = '';
    @track impact;
    @track reason = '';
    @track explanation = '';

    reasonOptions = [
        { label: 'Data Entry Correction', value: 'Data_Entry_Correction' },
        { label: 'Amendment',             value: 'Amendment' },
        { label: 'Restructuring',         value: 'Restructuring' },
        { label: 'Audit Reconciliation',  value: 'Audit_Reconciliation' },
        { label: 'Other',                 value: 'Other' }
    ];

    async connectedCallback() {
        this.impact = await preview({
            recordId: this.recordId,
            objectApiName: this.objectApiName,
            fieldApiName: this.fieldApiName,
            newValue: this.proposedValue
        });
    }

    get hasOriginalValue()  { return !!this.originalValue; }
    get hasAffectedCalcs()  { return this.impact?.affectedCalcs?.length > 0; }
    get affectedCalcsCount(){ return this.impact?.affectedCalcs?.length || 0; }
    get hasDownstream()     { return this.impact?.downstreamStale?.length > 0; }
    get cannotProceed()     { return !this.reason || !this.explanation || this.explanation.length < 20; }

    handleReasonChange(event)      { this.reason      = event.detail.value; }
    handleExplanationChange(event) { this.explanation = event.detail.value; }
    handleCancel()                 { this.dispatchEvent(new CustomEvent('cancel')); }

    async handleProceed() {
        const result = await commitCascade({
            recordId: this.recordId, objectApiName: this.objectApiName,
            fieldApiName: this.fieldApiName, newValue: this.proposedValue,
            reason: this.reason, explanation: this.explanation
        });
        this.dispatchEvent(new CustomEvent('cascadecommitted', { detail: result }));
    }
}
