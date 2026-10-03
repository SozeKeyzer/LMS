import { LightningElement, api, wire, track } from 'lwc';
import getReadiness from '@salesforce/apex/CalcReadinessController.getReadiness';
import preview from '@salesforce/apex/CalcReadinessController.preview';
import generate from '@salesforce/apex/CalcReadinessController.generate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import CalcPreviewModal from 'c/calcPreviewModal';

export default class CalcReadinessPanel extends LightningElement {
    @api recordId;
    @api objectApiName;
    @track calcs = [];
    @track modeIsManual = false;
    @track loadingCalc = null;
    wiredResult;

    @wire(getReadiness, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.calcs = result.data.map(c => ({
                ...c,
                hasMissingFields: c.missingFields && c.missingFields.length > 0,
                itemClass: this.itemClassForStatus(c.status),
                isScheduled: c.triggerEvent === 'Scheduled',
                previewDisabled: c.status === 'Blocked' || c.status === 'Error',
                runDisabled: c.status === 'Blocked' || c.status === 'Error'
            }));
        }
    }

    itemClassForStatus(s) {
        const base = 'calc-item ';
        return base + ({ Ready: 'calc-item-ready', Blocked: 'calc-item-blocked',
                         Stale: 'calc-item-stale', Error: 'calc-item-error' }[s] || '');
    }

    get hasCalcs() { return this.calcs.length > 0; }

    get summaryLabel() {
        const ready   = this.calcs.filter(c => c.status === 'Ready').length;
        const blocked = this.calcs.filter(c => c.status === 'Blocked' || c.status === 'Error').length;
        const total   = this.calcs.length;
        return blocked > 0 ? `${blocked} Blocked` : `${ready} of ${total} Ready`;
    }

    async handlePreview(event) {
        const calc = event.currentTarget.dataset.calc;
        this.loadingCalc = calc;
        try {
            const raw = await preview({ calcDeveloperName: calc, recordId: this.recordId });
            const previewData = JSON.parse(raw);

            if (!previewData.success) {
                this._showError('Preview Failed', previewData.errorMessage || 'Calculation returned an error.');
                return;
            }

            const outcome = await CalcPreviewModal.open({
                size: 'medium',
                calc,
                recordId: this.recordId,
                previewData
            });

            if (outcome?.editInputs) {
                // eslint-disable-next-line no-restricted-globals
                window.location.href = `/lightning/r/${this.objectApiName || 'Debt_Position__c'}/${this.recordId}/edit`;
            } else if (outcome?.generated) {
                refreshApex(this.wiredResult);
            }
        } catch (err) {
            this._showError('Preview Error', err.body?.message || err.message || 'Unexpected error during preview.');
        } finally {
            this.loadingCalc = null;
        }
    }

    async handleGenerate(event) {
        const calc = event.currentTarget.dataset.calc;
        this.loadingCalc = calc;
        try {
            const raw = await generate({ calcDeveloperName: calc, recordId: this.recordId });
            const result = JSON.parse(raw);
            this.dispatchEvent(new ShowToastEvent({
                title: result.success ? 'Done' : 'Failed',
                message: result.success
                    ? `Produced ${result.outputRows?.length || 0} rows`
                    : result.errorMessage,
                variant: result.success ? 'success' : 'error'
            }));
            refreshApex(this.wiredResult);
            this.dispatchEvent(new CustomEvent('calcgenerated'));
        } catch (err) {
            this._showError('Run Error', err.body?.message || err.message || 'Unexpected error during generate.');
        } finally {
            this.loadingCalc = null;
        }
    }

    scrollToField(event) {
        this.dispatchEvent(new CustomEvent('focusfield',
            { detail: { field: event.currentTarget.dataset.field } }));
    }

    _showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}
