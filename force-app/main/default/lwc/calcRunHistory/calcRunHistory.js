import { LightningElement, api, wire, track } from 'lwc';
import getRuns from '@salesforce/apex/CalcRunHistoryController.getRuns';

export default class CalcRunHistory extends LightningElement {
    @api recordId;
    @api objectApiName = 'Debt_Position__c';
    @track filterCalc = '';
    @track filterFrom = '';
    @track allRuns = [];
    calcOptions = [{ label: 'All', value: '' }];

    @wire(getRuns, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wired({ data }) {
        if (data) {
            this.allRuns = data;
            const names = [...new Set(data.map(r => r.Calc_Definition__c).filter(Boolean))];
            this.calcOptions = [
                { label: 'All', value: '' },
                ...names.map(n => ({ label: n, value: n }))
            ];
        }
    }

    get filteredRuns() {
        return this.allRuns
            .filter(r =>
                (!this.filterCalc || r.Calc_Definition__c === this.filterCalc) &&
                (!this.filterFrom  || r.Run_At__c >= this.filterFrom)
            )
            .map(r => ({
                ...r,
                outputCountLabel: (r.Output_Count__c || 0) + ' rows produced',
                dotClass: 'run-dot ' + (
                    r.Status__c === 'Success' ? 'run-dot-success' :
                    r.Status__c === 'Failed'  ? 'run-dot-error'   : 'run-dot-skipped'
                )
            }));
    }

    get hasRuns() { return this.filteredRuns.length > 0; }

    handleFilterCalc(event) { this.filterCalc = event.detail.value; }
    handleFilterFrom(event) { this.filterFrom = event.detail.value; }
}
