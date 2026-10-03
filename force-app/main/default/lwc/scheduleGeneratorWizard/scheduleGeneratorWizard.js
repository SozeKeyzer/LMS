import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getStatus from '@salesforce/apex/ScheduleGenerationController.getStatus';
import getDraftRows from '@salesforce/apex/ScheduleGenerationController.getDraftRows';
import generateDraft from '@salesforce/apex/ScheduleGenerationController.generateDraft';
import submitForReview from '@salesforce/apex/ScheduleGenerationController.submitForReview';

const COLUMNS = [
    { label: 'Period Start', fieldName: 'periodStart', type: 'date-local' },
    { label: 'Period End',   fieldName: 'periodEnd',   type: 'date-local' },
    { label: 'Due Date',     fieldName: 'dueDate',     type: 'date-local' },
    { label: 'Principal Due', fieldName: 'principalDue', type: 'number',
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
    { label: 'Rate Status', fieldName: 'rateFinalisationStatus', type: 'text' }
];

export default class ScheduleGeneratorWizard extends LightningElement {
    @api recordId;

    @track status;
    @track draftRows = [];
    @track notes = '';
    @track isGenerating = false;
    @track isSubmitting = false;

    columns = COLUMNS;

    _statusResult;
    _rowsResult;

    @wire(getStatus, { dpId: '$recordId' })
    wiredStatus(result) {
        this._statusResult = result;
        if (result.data) this.status = result.data;
    }

    @wire(getDraftRows, { dpId: '$recordId' })
    wiredRows(result) {
        this._rowsResult = result;
        if (result.data) this.draftRows = result.data;
    }

    // ── Progress indicator ───────────────────────────────────────────────────

    get currentStep() {
        return this.status?.scheduleGenerationStatus ?? 'Not_Generated';
    }

    // ── Section visibility ────────────────────────────────────────────────────

    get isBusy() {
        return this.isGenerating || this.isSubmitting;
    }

    get isNotGenerated() {
        return this.currentStep === 'Not_Generated';
    }

    get isDraft() {
        return this.currentStep === 'Draft';
    }

    get isPendingReview() {
        return this.currentStep === 'Pending_Review';
    }

    get isActive() {
        return this.currentStep === 'Active';
    }

    get hasRejectReason() {
        return this.isNotGenerated && !!this.status?.lastRejectReason;
    }

    get pendingReviewMessage() {
        return `Submitted for checker review${this.status?.makerName ? ' by ' + this.status.makerName : ''}. Awaiting approval.`;
    }

    get activeMessage() {
        const checker = this.status?.checkerName ? ' by ' + this.status.checkerName : '';
        return `Schedule is Active — approved${checker}.`;
    }

    // ── Pre-conditions ────────────────────────────────────────────────────────

    get preconditionItems() {
        const failures = this.status?.preconditionFailures ?? [];
        return failures.map((msg, idx) => ({ key: idx, message: msg }));
    }

    get hasFailures() {
        return this.preconditionItems.length > 0;
    }

    get generateDisabled() {
        return this.hasFailures || this.isBusy;
    }

    get submitDisabled() {
        return this.isBusy || this.draftRows.length === 0;
    }

    get rowCountLabel() {
        return `${this.draftRows.length} period${this.draftRows.length === 1 ? '' : 's'} generated`;
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    async handleGenerate() {
        this.isGenerating = true;
        try {
            await generateDraft({ dpId: this.recordId });
            this._toast('success', 'Draft schedule generated', 'Review the rows below before submitting.');
            await this._refreshAll();
        } catch (err) {
            this._toast('error', 'Generation failed', this._errMsg(err));
        } finally {
            this.isGenerating = false;
        }
    }

    async handleSubmit() {
        this.isSubmitting = true;
        try {
            await submitForReview({ dpId: this.recordId, notes: this.notes });
            this._toast('success', 'Submitted for review', 'A checker will approve or reject this schedule.');
            this.notes = '';
            await this._refreshAll();
        } catch (err) {
            this._toast('error', 'Submission failed', this._errMsg(err));
        } finally {
            this.isSubmitting = false;
        }
    }

    async _refreshAll() {
        await Promise.all([refreshApex(this._statusResult), refreshApex(this._rowsResult)]);
    }

    _toast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _errMsg(err) {
        return err?.body?.message ?? err?.message ?? 'An unexpected error occurred.';
    }
}
