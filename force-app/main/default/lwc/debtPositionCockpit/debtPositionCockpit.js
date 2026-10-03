import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CALC_MODE_FIELD from '@salesforce/schema/Debt_Position__c.Calc_Mode__c';
import CALC_MODE_SINCE_FIELD from '@salesforce/schema/Debt_Position__c.Calc_Mode_Since__c';

const FIELDS = [CALC_MODE_FIELD, CALC_MODE_SINCE_FIELD];

export default class DebtPositionCockpit extends LightningElement {
    @api recordId;

    @track calcMode      = 'Engine';
    @track calcModeSince = '';
    @track showCascadePanel = false;
    @track cascadeField     = '';
    @track cascadeOldValue  = '';
    @track cascadeNewValue  = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (data) {
            this.calcMode      = getFieldValue(data, CALC_MODE_FIELD) || 'Engine';
            this.calcModeSince = getFieldValue(data, CALC_MODE_SINCE_FIELD) || '';
        }
    }

    cascadeFieldOptions = [
        { label: 'Day Count Convention',  value: 'Day_Count_Convention__c' },
        { label: 'Initial Margin',        value: 'Initial_Margin__c' },
        { label: 'PIK Default Mode',      value: 'PIK_Default_Mode__c' },
        { label: 'Interest Reserve Mode', value: 'Interest_Reserve_Default_Mode__c' },
        { label: 'Initial Benchmark',     value: 'Initial_Benchmark__c' }
    ];

    get cannotPreviewCascade() {
        return !this.cascadeField || !this.cascadeNewValue;
    }

    handleCascadeFieldChange(event) { this.cascadeField    = event.detail.value; }
    handleOldValueChange(event)     { this.cascadeOldValue = event.detail.value; }
    handleNewValueChange(event)     { this.cascadeNewValue = event.detail.value; }

    handlePreviewCascade()   { this.showCascadePanel = true; }
    handleCascadeCancel()    { this.showCascadePanel = false; }

    handleCascadeCommitted() {
        this.showCascadePanel = false;
        this.cascadeField     = '';
        this.cascadeOldValue  = '';
        this.cascadeNewValue  = '';
    }

    // Called by calcReadinessPanel after a successful Generate so the chart
    // immediately shows the new schedule without waiting for cache expiry.
    handleCalcGenerated() {
        const chart = this.template.querySelector('c-cashflow-chart');
        if (chart) chart.refresh();
    }
}
