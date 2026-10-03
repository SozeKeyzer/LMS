import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getEventDetails from '@salesforce/apex/RateApplicationConfirmController.getEventDetails';
import submitDecision from '@salesforce/apex/RateApplicationConfirmController.submitDecision';

const PCT = new Intl.NumberFormat('en-GB', {
    style: 'percent', minimumFractionDigits: 3, maximumFractionDigits: 4
});

const DECISION_LABELS = {
    Apply:              'Applied — rate applied effective today',
    Defer:              'Deferred — application rescheduled',
    Waive_Period:       'Waived for this period only',
    Waive_Permanently:  'Permanently waived — IRT superseded'
};

export default class RateApplicationConfirm extends LightningElement {
    @api recordId;

    @track eventDetails;
    @track error;
    @track isLoading = true;
    @track isSubmitting = false;

    @track selectedDecision = '';
    @track deferDate = '';
    @track reason = '';

    _wiredResult;

    @wire(getEventDetails, { raeId: '$recordId' })
    wiredDetails(result) {
        this._wiredResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this.eventDetails = data;
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message ?? 'An unexpected error occurred.';
            this.eventDetails = undefined;
        }
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get hasData() {
        return !!this.eventDetails;
    }

    get displayRate() {
        const d = this.eventDetails;
        if (!d) return '—';
        if (d.pricingBasis === 'Fixed' && d.fixedRate != null) {
            return this._pctFmt(d.fixedRate);
        }
        if (d.spread != null) {
            return this._pctFmt(d.spread) + ' spread';
        }
        return '—';
    }

    get actualAppDateLabel() {
        const d = this.eventDetails;
        return (d?.actualAppDate) ? d.actualAppDate : 'Not yet applied';
    }

    get isDeferSelected() {
        return this.selectedDecision === 'Defer';
    }

    get isReasonRequired() {
        return this.selectedDecision === 'Defer' ||
               this.selectedDecision === 'Waive_Period' ||
               this.selectedDecision === 'Waive_Permanently';
    }

    get reasonLabel() {
        return this.isReasonRequired ? 'Reason (required)' : 'Reason (optional)';
    }

    get isSubmitDisabled() {
        if (!this.selectedDecision) return true;
        if (this.selectedDecision === 'Defer' && !this.deferDate) return true;
        if (this.isReasonRequired && !this.reason.trim()) return true;
        return false;
    }

    get todayIso() {
        return new Date().toISOString().substring(0, 10);
    }

    get decisionSummary() {
        const d = this.eventDetails;
        if (!d) return '';
        const label = DECISION_LABELS[d.decisionType] ?? d.decisionType;
        const date  = d.decisionDate ? ' on ' + d.decisionDate : '';
        const defer = d.newApplicationDate ? ' · Deferred to ' + d.newApplicationDate : '';
        const rsn   = d.reason ? ' · ' + d.reason : '';
        return label + date + defer + rsn;
    }

    // Decision button classes
    get applyButtonClass()       { return this._btnClass('Apply'); }
    get deferButtonClass()       { return this._btnClass('Defer'); }
    get waivePeriodButtonClass() { return this._btnClass('Waive_Period'); }
    get waivedPermButtonClass()  { return this._btnClass('Waive_Permanently'); }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleDecisionSelect(event) {
        this.selectedDecision = event.currentTarget.dataset.value;
        if (this.selectedDecision !== 'Defer') {
            this.deferDate = '';
        }
    }

    handleDeferDateChange(event) {
        this.deferDate = event.detail.value;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    handleCancel() {
        this.selectedDecision = '';
        this.deferDate = '';
        this.reason = '';
    }

    handleSubmit() {
        this.isSubmitting = true;
        submitDecision({
            raeId:        this.recordId,
            decisionType: this.selectedDecision,
            reason:       this.reason || null,
            deferDate:    this.deferDate || null
        })
        .then(() => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Decision submitted',
                message: DECISION_LABELS[this.selectedDecision] ?? this.selectedDecision,
                variant: 'success'
            }));
            this.selectedDecision = '';
            this.deferDate = '';
            this.reason = '';
            return refreshApex(this._wiredResult);
        })
        .catch(err => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Submission failed',
                message: err?.body?.message ?? 'An unexpected error occurred.',
                variant: 'error',
                mode: 'sticky'
            }));
        })
        .finally(() => {
            this.isSubmitting = false;
        });
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    _btnClass(decision) {
        const base = 'decision-btn';
        return this.selectedDecision === decision ? base + ' decision-btn_selected' : base;
    }

    _pctFmt(val) {
        if (val == null) return '—';
        // IRT rates stored as decimal (e.g. 0.065 for 6.5%) or as whole number (6.5)?
        // Assuming stored as decimal fraction (0.065)
        try { return PCT.format(val); }
        catch (e) { return String(val); }
    }
}
