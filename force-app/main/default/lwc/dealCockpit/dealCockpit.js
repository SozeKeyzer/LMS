import { LightningElement, api, wire, track } from 'lwc';
import getSummary from '@salesforce/apex/DealCockpitController.getSummary';

export default class DealCockpit extends LightningElement {
    @api recordId;
    @track tranches = [];
    @track errorMessage;
    @track fallbackReason;

    @wire(getSummary, { financialInstrumentId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.tranches       = data.tranches || [];
            this.fallbackReason = data.fallbackReason || null;
            this.errorMessage   = null;
        } else if (error) {
            this.errorMessage = error.body?.message || error.message || JSON.stringify(error);
            this.tranches     = [];
        }
    }

    get hasError()    { return !!this.errorMessage; }
    get hasFallback() { return !!this.fallbackReason; }

    get kpis() {
        return {
            totalCommitted:   '—',
            trancheCount:     this.tranches.length,
            totalOutstanding: '—',
            outstandingDelta: '',
            avgRate:          '—',
            avgRateNote:      '',
            avgMaturity:      '—',
            earliestMaturity: '',
            ytdIncome:        '—',
            holderCount:      '—'
        };
    }

    trancheColumns = [
        { label: 'Tranche',   fieldName: 'Name' },
        { label: 'Margin',    fieldName: 'marginDisplay' },
        { label: 'Benchmark', fieldName: 'Initial_Benchmark__c' },
        { label: 'Day Count', fieldName: 'Day_Count_Convention__c' },
        { label: 'Calc Mode', fieldName: 'Calc_Mode__c' },
        { type: 'action', typeAttributes: { rowActions: [{ label: 'Open', name: 'open' }] } }
    ];

    get formattedTranches() {
        return this.tranches.map(t => ({
            ...t,
            marginDisplay: t.Initial_Margin__c != null
                ? Number(t.Initial_Margin__c).toFixed(4) + '%'
                : '—'
        }));
    }

    openTranche(event) {
        const row = event.detail.row;
        // eslint-disable-next-line no-restricted-globals
        window.location.href = '/lightning/r/Debt_Position__c/' + row.Id + '/view';
    }
}
