import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getScheduleComparison from '@salesforce/apex/AmendmentProjectionComparisonController.getScheduleComparison';
import generatePreview from '@salesforce/apex/AmendmentProjectionComparisonController.generatePreview';

const NUM = new Intl.NumberFormat('en-GB', {
    minimumFractionDigits: 2, maximumFractionDigits: 2
});

export default class AmendmentPreviewView extends LightningElement {
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

    // ── Generate Preview ──────────────────────────────────────────────────────

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

    // ── Getters ───────────────────────────────────────────────────────────────

    get hasData() {
        return !!this.comparisonResult;
    }

    get hasProjection() {
        return !!this.comparisonResult?.projectionSummary;
    }

    get hasEnrichedRows() {
        return (this.comparisonResult?.enrichedRows?.length ?? 0) > 0;
    }

    get enrichedRows() {
        return this.comparisonResult?.enrichedRows ?? [];
    }

    get impact() {
        return this.comparisonResult?.impactSummary ?? {
            periodsAffected:      0,
            currentInterestFmt:   '—',
            projectedInterestFmt: '—',
            deltaInterestFmt:     '—',
            deltaClass:           'kpi-tile__value'
        };
    }

    get generateButtonLabel() {
        return this.hasProjection ? 'Regenerate Preview' : 'Generate Preview';
    }

    get generateButtonVariant() {
        return this.hasProjection ? 'neutral' : 'brand';
    }

    get isGenerateDisabled() {
        return this.isGenerating || this.isLoading;
    }

    get effectiveDateLabel() {
        const r = this.comparisonResult;
        if (!r) return '';
        return r.actualEffectiveDate ?? r.proposedEffectiveDate ?? 'Not set';
    }

    get projectionSubtitle() {
        const ps = this.comparisonResult?.projectionSummary;
        if (!ps) return '';
        const dt = ps.generatedDateTime
            ? new Date(ps.generatedDateTime).toLocaleString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
                hour: '2-digit', minute: '2-digit'
            })
            : '—';
        return (ps.projectionType ?? 'Preview') + ' · ' + (ps.status ?? '') + ' · Generated ' + dt;
    }

    get amendmentStatusBadgeClass() {
        const s = this.comparisonResult?.amendmentStatus;
        if (s === 'Effective')         return 'meta-strip__badge meta-strip__badge_effective';
        if (s === 'Approved')          return 'meta-strip__badge meta-strip__badge_approved';
        if (s === 'Pending Approval')  return 'meta-strip__badge meta-strip__badge_pending';
        return 'meta-strip__badge meta-strip__badge_neutral';
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    _enrich(data) {
        const rawCurrent = data.currentSchedule ?? [];
        const projRows   = data.projectionSummary?.projectedRows ?? [];

        // projRows align positionally with affected current rows, in period order
        let projIdx = 0;
        let currentInterestSum  = 0;
        let projInterestSum     = 0;
        let periodsAffected     = 0;

        const enrichedRows = rawCurrent.map(function(row) {
            const isAffected = !!row.isAffectedByAmend;
            const proj = isAffected && projIdx < projRows.length ? projRows[projIdx] : null;
            if (isAffected) {
                projIdx++;
                periodsAffected++;
                currentInterestSum += row.interestDue  ?? 0;
                projInterestSum    += proj?.interestDue ?? 0;
            }

            const delta = (proj?.interestDue != null && row.interestDue != null)
                ? proj.interestDue - row.interestDue : null;

            return {
                key:               row.recordId,
                periodLabel:       this._periodLabel(row.periodStart, row.periodEnd),
                principalFmt:      this._fmt(row.principalDue),
                interestFmt:       this._fmt(row.interestDue),
                totalFmt:          this._fmt(row.totalDue),
                projPrincipalFmt:  proj ? this._fmt(proj.principalDue) : '—',
                projInterestFmt:   proj ? this._fmt(proj.interestDue)  : '—',
                projTotalFmt:      proj ? this._fmt(proj.totalDue)     : '—',
                deltaFmt:          this._fmtDelta(delta),
                deltaClass:        'mono ' + this._deltaModifier(delta),
                isAffectedByAmend: isAffected,
                rowClass:          isAffected ? 'affected-row' : '',
                status:            row.status
            };
        }, this);

        // Pre-computed impact summary (numbers resolved here, not in getter)
        let impactSummary = null;
        if (data.projectionSummary) {
            const delta = projInterestSum - currentInterestSum;
            impactSummary = {
                periodsAffected:      periodsAffected,
                currentInterestFmt:   this._fmt(currentInterestSum),
                projectedInterestFmt: this._fmt(projInterestSum),
                deltaInterestFmt:     this._fmtDelta(delta),
                deltaClass:           'kpi-tile__value ' + this._deltaModifier(delta)
            };
        }

        return Object.assign({}, data, {
            enrichedRows:  enrichedRows,
            impactSummary: impactSummary
        });
    }

    _periodLabel(start, end) {
        if (start && end) return start + ' – ' + end;
        return start || end || '—';
    }

    _fmt(amount) {
        if (amount == null) return '—';
        try { return NUM.format(amount); }
        catch (e) { return String(amount); }
    }

    _fmtDelta(delta) {
        if (delta == null) return '—';
        const prefix = delta > 0 ? '+' : '';
        try { return prefix + NUM.format(delta); }
        catch (e) { return (delta > 0 ? '+' : '') + String(delta); }
    }

    _deltaModifier(delta) {
        if (delta == null || delta === 0) return '';
        return delta > 0 ? 'delta-positive' : 'delta-negative';
    }
}
