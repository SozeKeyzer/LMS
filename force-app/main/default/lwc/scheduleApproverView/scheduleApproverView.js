import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getStatus from '@salesforce/apex/ScheduleGenerationController.getStatus';
import getDraftRows from '@salesforce/apex/ScheduleGenerationController.getDraftRows';
import approveApex from '@salesforce/apex/ScheduleGenerationController.approve';
import rejectApex from '@salesforce/apex/ScheduleGenerationController.reject';

const COLUMNS = [
    { label: 'Period Start', fieldName: 'periodStart', type: 'date-local' },
    { label: 'Period End',   fieldName: 'periodEnd',   type: 'date-local' },
    { label: 'Due Date',     fieldName: 'dueDate',     type: 'date-local' },
    { label: 'Principal Due', fieldName: 'principalDue', type: 'number',
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
    { label: 'Rate Status', fieldName: 'rateFinalisationStatus', type: 'text' }
];

export default class ScheduleApproverView extends LightningElement {
    @api recordId;

    @track status;
    @track draftRows = [];
    @track notes = '';
    @track reason = '';
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

    get shouldRender() {
        return this.status?.scheduleGenerationStatus === 'Pending_Review';
    }

    get isSelfReview() {
        return this.status && this.status.makerId === this.status.currentUserId;
    }

    get rowCountLabel() {
        return `${this.draftRows.length} period${this.draftRows.length === 1 ? '' : 's'} awaiting approval`;
    }

    get rejectDisabled() {
        return this.isSubmitting || !this.reason || !this.reason.trim();
    }

    get approveDisabled() {
        return this.isSubmitting;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    async handleApprove() {
        this.isSubmitting = true;
        try {
            await approveApex({ dpId: this.recordId, notes: this.notes });
            this._toast('success', 'Schedule approved', 'The schedule is now Active.');
            await this._refreshAll();
        } catch (err) {
            this._toast('error', 'Approval failed', this._errMsg(err));
        } finally {
            this.isSubmitting = false;
        }
    }

    async handleReject() {
        this.isSubmitting = true;
        try {
            await rejectApex({ dpId: this.recordId, reason: this.reason });
            this._toast('success', 'Schedule rejected', 'The maker can regenerate a corrected draft.');
            this.reason = '';
            await this._refreshAll();
        } catch (err) {
            this._toast('error', 'Rejection failed', this._errMsg(err));
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
