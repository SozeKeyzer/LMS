import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import generate from '@salesforce/apex/CalcReadinessController.generate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PS_COLUMNS = [
    { label: 'Period Start', fieldName: 'Period_Start__c', type: 'date-local' },
    { label: 'Period End',   fieldName: 'Period_End__c',   type: 'date-local' },
    { label: 'Due Date',     fieldName: 'Due_Date__c',     type: 'date-local' },
    { label: 'Principal',    fieldName: 'Principal_Due__c', type: 'currency' },
    { label: 'Interest',     fieldName: 'Interest_Due__c',  type: 'currency' },
    { label: 'Total',        fieldName: 'Total_Due__c',     type: 'currency' }
];

const ACCRUAL_COLUMNS = [
    { label: 'Date',       fieldName: 'Accrual_Date__c',       type: 'date-local' },
    { label: 'Principal',  fieldName: 'Principal_Basis__c',    type: 'currency' },
    { label: 'Rate',       fieldName: 'Rate__c',               type: 'percent',
      typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 4 } },
    { label: 'Day Frac',   fieldName: 'Day_Count_Fraction__c', type: 'number',
      typeAttributes: { minimumFractionDigits: 6, maximumFractionDigits: 6 } },
    { label: 'Accrual',    fieldName: 'Accrued_Amount__c',     type: 'currency' }
];

export default class CalcPreviewModal extends LightningModal {
    @api calc;
    @api recordId;
    @api previewData;

    get isAccrual() {
        return this.calc && this.calc.endsWith('_Interest_Accrual');
    }

    get columns()  { return this.isAccrual ? ACCRUAL_COLUMNS : PS_COLUMNS; }
    get keyField() { return 'External_Id__c'; }

    get rows() {
        return (this.previewData?.outputRows || []).map(r => ({
            ...r,
            Total_Due__c: r.Total_Due__c != null
                ? r.Total_Due__c
                : (r.Principal_Due__c || 0) + (r.Interest_Due__c || 0) + (r.Fees_Due__c || 0)
        }));
    }

    get hasRows()  { return this.rows.length > 0; }
    get isEmpty()  { return this.rows.length === 0; }

    get emptyMessage() {
        const note = this.previewData?.inputsSnapshot?.note;
        if (note) return note;
        return 'No rows were projected. Check that all required inputs are set on this record.';
    }

    get totals() {
        const rows = this.rows;
        if (this.isAccrual) {
            const total = rows.reduce((s, r) => s + (r.Accrued_Amount__c || 0), 0);
            return {
                count:  rows.length,
                label1: 'Total Accrual',
                val1:   '$' + total.toFixed(2),
                label2: 'Period Days',
                val2:   rows.length
            };
        }
        const principal = rows.reduce((s, r) => s + (r.Principal_Due__c || 0), 0);
        const interest  = rows.reduce((s, r) => s + (r.Interest_Due__c  || 0), 0);
        return {
            count:  rows.length,
            label1: 'Total Principal',
            val1:   '$' + principal.toFixed(2),
            label2: 'Total Interest',
            val2:   '$' + interest.toFixed(2)
        };
    }

    handleCancel()     { this.close({ generated: false }); }
    handleEditInputs() { this.close({ editInputs: true }); }

    async handleGenerate() {
        try {
            const raw    = await generate({ calcDeveloperName: this.calc, recordId: this.recordId });
            const result = JSON.parse(raw);
            if (!result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Generate Failed', message: result.errorMessage, variant: 'error'
                }));
                return;
            }
            this.close({ generated: true, result });
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Generate Error',
                message: err.body?.message || err.message || 'Unexpected error.',
                variant: 'error'
            }));
        }
    }
}
