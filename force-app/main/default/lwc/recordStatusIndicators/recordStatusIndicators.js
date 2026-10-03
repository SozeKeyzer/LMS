import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getIndicators from '@salesforce/apex/StatusIndicatorController.getIndicators';

export default class RecordStatusIndicators extends NavigationMixin(LightningElement) {
    /** Injected automatically by the record page host */
    @api recordId;
    @api objectApiName;

    /** Configurable via Lightning App Builder */
    @api hideWhenEmpty = false;
    @api cardTitle = 'Status Indicators';

    indicators = [];
    isLoading  = true;
    error;

    // ─── Wire ──────────────────────────────────────────────────────────────────

    @wire(getIndicators, { recordId: '$recordId', parentObjectApiName: '$objectApiName' })
    wiredIndicators({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.indicators = data.map((i) => this._decorate(i));
            this.error      = undefined;
        } else if (error) {
            this.error      = error?.body?.message ?? 'Unable to load status indicators.';
            this.indicators = [];
        }
    }

    // ─── Getters ───────────────────────────────────────────────────────────────

    get hasIndicators() {
        return this.indicators.length > 0;
    }

    /**
     * Controls whether the card article renders at all.
     * Keeps the DOM clean when hideWhenEmpty = true and there is nothing to show.
     */
    get showCard() {
        if (this.isLoading) return true;  // show skeleton
        if (this.error)     return true;  // always show error
        if (this.hideWhenEmpty && !this.hasIndicators) return false;
        return true;
    }

    // ─── Click handler ─────────────────────────────────────────────────────────

    handleClick(event) {
        event.preventDefault();
        const devName   = event.currentTarget.dataset.dev;
        const indicator = this.indicators.find((i) => i.developerName === devName);
        if (!indicator) return;

        // Latest_Record mode → navigate to that specific record
        if (indicator.isLatest && indicator.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: indicator.recordId, actionName: 'view' }
            });
            return;
        }

        // Active_Count mode → navigate to the parent's related list
        if (indicator.relatedListName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordRelationshipPage',
                attributes: {
                    recordId:            this.recordId,
                    objectApiName:       this.objectApiName,
                    relationshipApiName: indicator.relatedListName,
                    actionName:          'view'
                }
            });
        }
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    _decorate(i) {
        return {
            ...i,
            cssClass:      `indicator ${i.variant ?? 'neutral'}`,
            isCount:       i.mode === 'Active_Count',
            isLatest:      i.mode === 'Latest_Record',
            statusPillClass: this._statusPillClass(i.statusValue),
            iconName:      this._resolveIcon(i.icon)
        };
    }

    _statusPillClass(value) {
        if (!value) return 'status-pill';
        const v = value.toLowerCase();
        if (v === 'completed' || v.includes('pass') || v === 'compliant') {
            return 'status-pill passed';
        }
        if (v === 'failed' || v.includes('fail') || v === 'breached') {
            return 'status-pill failed';
        }
        if (v === 'waived') {
            return 'status-pill waived';
        }
        return 'status-pill';
    }

    /** Normalises icon values: accepts 'utility:warning' or bare 'warning'. */
    _resolveIcon(raw) {
        if (!raw) return 'utility:info';
        return raw.includes(':') ? raw : `utility:${raw}`;
    }
}
