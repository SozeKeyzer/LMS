import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getScheduleComparison from '@salesforce/apex/AmendmentProjectionComparisonController.getScheduleComparison';
import generatePreview from '@salesforce/apex/AmendmentProjectionComparisonController.generatePreview';

const GBP = new Intl.NumberFormat('en-GB', {
    style: 'currency', currency: 'GBP', minimumFractionDigits: 2
});

export default class AmendmentProjectionComparison extends LightningElement {
    @api recordId;

    @track comparisonResult;
    @track error;
    @track isLoading = true;
    @track isGenerating = false;

    _wiredResult;

    @wire(getScheduleComparison, { amendmentId: '$recordId' })
    wiredComparison(result) {
        this._wiredResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this.comparisonResult = this._enrich(data);
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message ?? 'An unexpected error occurred.';
            this.comparisonResult = undefined;
        }
    }

    handleGeneratePreview() {
        this.isGenerating = true;
        generatePreview({ amendmentId: this.recordId })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Preview generated',
                    message: 'Projection created and linked to this amendment.',
                    variant: 'success'
                }));
                return refreshApex(this._wiredResult);
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Preview generation failed',
                    message: err?.body?.message ?? 'An unexpected error occurred.',
                    variant: 'error',
                    mode: 'sticky'
                }));
            })
            .finally(() => {
                this.isGenerating = false;
            });
    }

    get hasData() { return !!this.comparisonResult; }
    get hasCurrentSchedule() { return this.comparisonResult?.currentSchedule?.length > 0; }
    get hasProjection() { return !!this.comparisonResult?.projectionSummary; }
    get hasProjectedRows() { return this.comparisonResult?.projectionSummary?.projectedRows?.length > 0; }
    get currentSchedule() { return this.comparisonResult?.currentSchedule ?? []; }
    get projectedRows() { return this.comparisonResult?.projectionSummary?.projectedRows ?? []; }
    get generateButtonLabel() { return this.hasProjection ? 'Regenerate Preview' : 'Generate Preview'; }
    get generateButtonVariant() { return this.hasProjection ? 'neutral' : 'brand'; }
    get isGenerateDisabled() { return this.isGenerating || this.isLoading; }

    get effectiveDateLabel() {
        const r = this.comparisonResult;
        if (!r) return '';
        const d = r.actualEffectiveDate ?? r.proposedEffectiveDate;
        return d ? d : 'Not set';
    }

    get currentScheduleSubtitle() {
        const rows = this.currentSchedule;
        const total = rows.length;
        const affected = rows.filter(function(r) { return r.isAffectedByAmend; }).length;
        if (total === 0) return 'No open rows';
        return total + ' open row' + (total !== 1 ? 's' : '') + ' · ' + affected + ' will be superseded';
    }

    get projectionSubtitle() {
        const ps = this.comparisonResult?.projectionSummary;
        if (!ps) return 'No projection generated';
        const dt = ps.generatedDateTime
            ? new Date(ps.generatedDateTime).toLocaleString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
                hour: '2-digit', minute: '2-digit'
            })
            : '—';
        return (ps.projectionType ?? 'Preview') + ' · ' + (ps.status ?? '') + ' · Generated ' + dt;
    }

    get impact() {
        const r = this.comparisonResult;
        if (!r?.projectionSummary) {
            return {
                periodsAffected: 0,
                currentInterestFmt: '—',
                projectedInterestFmt: '—',
                deltaInterestFmt: '—',
                deltaHeadingClass: 'slds-text-heading_medium'
            };
        }
        const affected  = (r.currentSchedule ?? []).filter(function(row) { return row.isAffectedByAmend; });
        const projected = r.projectionSummary.projectedRows ?? [];
        const currentInterest = affected.reduce(function(sum, row) { return sum + (row.interestDue ?? 0); }, 0);
        const projInterest    = projected.reduce(function(sum, row) { return sum + (row.interestDue ?? 0); }, 0);
        const delta = projInterest - currentInterest;
        return {
            periodsAffected:     affected.length,
            currentInterestFmt:  this._fmt(currentInterest),
            projectedInterestFmt: this._fmt(projInterest),
            deltaInterestFmt:    this._fmtDelta(delta),
            deltaHeadingClass:   'slds-text-heading_medium ' + this._deltaModifier(delta)
        };
    }

    _enrich(data) {
        const rawCurrent = data.currentSchedule ?? [];
        const affectedRaw = rawCurrent.filter(function(r) { return r.isAffectedByAmend; });

        const enrichedCurrent = rawCurrent.map(function(row) {
            return Object.assign({}, row, {
                key:          row.recordId,
                periodLabel:  this._periodLabel(row.periodStart, row.periodEnd),
                principalFmt: this._fmt(row.principalDue),
                interestFmt:  this._fmt(row.interestDue),
                totalFmt:     this._fmt(row.totalDue),
                rowClass:     row.isAffectedByAmend ? 'affected-row' : ''
            });
        }, this);

        let enrichedProjection = null;
        if (data.projectionSummary) {
            const projectedRows = (data.projectionSummary.projectedRows ?? []).map(function(row, i) {
                const match = affectedRaw[i];
                const delta = (row.interestDue != null && match?.interestDue != null)
                    ? row.interestDue - match.interestDue : null;
                return Object.assign({}, row, {
                    key:          'proj-' + i,
                    periodLabel:  this._periodLabel(row.periodStart, row.periodEnd),
                    principalFmt: this._fmt(row.principalDue),
                    interestFmt:  this._fmt(row.interestDue),
                    totalFmt:     this._fmt(row.totalDue),
                    deltaFmt:     this._fmtDelta(delta),
                    deltaClass:   'slds-truncate ' + this._deltaModifier(delta)
                });
            }, this);
            enrichedProjection = Object.assign({}, data.projectionSummary, { projectedRows: projectedRows });
        }

        return Object.assign({}, data, {
            currentSchedule:   enrichedCurrent,
            projectionSummary: enrichedProjection
        });
    }

    _periodLabel(start, end) {
        if (start && end) return start + ' – ' + end;
        return start || end || '—';
    }

    _fmt(amount) {
        if (amount == null) return '—';
        try { return GBP.format(amount); }
        catch (e) { return String(amount); }
    }

    _fmtDelta(delta) {
        if (delta == null) return '—';
        const prefix = delta > 0 ? '+' : '';
        try { return prefix + GBP.format(delta); }
        catch (e) { return (delta > 0 ? '+' : '') + String(delta); }
    }

    _deltaModifier(delta) {
        if (delta == null || delta === 0) return '';
        return delta > 0 ? 'delta-positive' : 'delta-negative';
    }
}
