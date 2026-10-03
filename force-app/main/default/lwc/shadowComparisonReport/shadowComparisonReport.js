import { LightningElement, api, wire, track } from 'lwc';
import getComparisons from '@salesforce/apex/ShadowComparisonController.getComparisons';

export default class ShadowComparisonReport extends LightningElement {
    @api calcDeveloperName;
    @track comparisons = [];

    @wire(getComparisons, { calcDeveloperName: '$calcDeveloperName' })
    wired({ data }) {
        if (data) {
            this.comparisons = data;
        }
    }

    columns = [
        { label: 'Record',      fieldName: 'Parent_Record_Id__c' },
        { label: 'Locked Ver',  fieldName: 'Locked_Version__c' },
        { label: 'Proposed Ver',fieldName: 'Proposed_Version__c' },
        { label: 'Differences', fieldName: 'Differences_Detected__c', type: 'boolean' },
        { label: 'Summary',     fieldName: 'Difference_Summary__c' },
        { label: 'Status',      fieldName: 'Status__c' },
        { type: 'action', typeAttributes: { rowActions: [{ label: 'Review', name: 'review' }] } }
    ];

    get totalRuns()       { return this.comparisons.length; }
    get differencesCount(){ return this.comparisons.filter(c => c.Differences_Detected__c).length; }
    get reviewedCount()   { return this.comparisons.filter(c => c.Status__c === 'Reviewed').length; }
    get noReviewed()      { return !this.comparisons.some(c => c.Status__c === 'Reviewed'); }
    get hasDifferences()  { return this.differencesCount > 0; }
    get diffBadgeLabel()  { return `${this.differencesCount} Difference${this.differencesCount !== 1 ? 's' : ''}`; }
    get diffStatClass()   { return this.differencesCount > 0 ? 'stat-value-warn' : 'stat-value'; }

    get largestDiff() {
        const diffs = this.comparisons
            .filter(c => c.Differences_Detected__c && c.Difference_Summary__c)
            .map(c => c.Difference_Summary__c);
        return diffs.length > 0 ? diffs[0] : 'N/A';
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row    = event.detail.row;
        if (action.name === 'review') {
            this.comparisons = this.comparisons.map(c =>
                c.Id === row.Id ? { ...c, Status__c: 'Reviewed' } : c
            );
        }
    }

    handleApproveAndPromote() {
        this.dispatchEvent(new CustomEvent('approveandpromote', {
            detail: { calcDeveloperName: this.calcDeveloperName }
        }));
    }

    handleExport() {
        this.dispatchEvent(new CustomEvent('export'));
    }
}
