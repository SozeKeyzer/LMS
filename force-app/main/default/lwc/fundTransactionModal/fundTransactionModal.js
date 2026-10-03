import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }    from 'lightning/platformShowToastEvent';
import saveTransaction       from '@salesforce/apex/FundTransactionController.saveTransaction';
import getEntityByExternalId from '@salesforce/apex/FundTransactionController.getEntityByExternalId';
import getTransactionById    from '@salesforce/apex/FundTransactionController.getTransactionById';
import USER_ID               from '@salesforce/user/Id';

const TX_TYPE_OPTIONS = [
    { label: 'New Application', value: 'New Application' },
    { label: 'Fund Switch In',  value: 'Fund Switch In' },
    { label: 'Fund Redemption', value: 'Fund Redemption' },
    { label: 'Fund Switch Out', value: 'Fund Switch Out' }
];

const VEHICLE_TYPE_OPTIONS = [
    { label: 'Fund',                 value: 'Fund' },
    { label: 'Financial Instrument', value: 'Financial Instrument' },
    { label: 'Warehouse Note',       value: 'Warehouse Note' }
];

const MONTH_NAMES = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];

const SWITCH_TYPES = new Set(['Fund Switch In', 'Fund Switch Out']);

export default class FundTransactionModal extends LightningElement {
    @api recordId;

    @track record = {
        Transaction_Date__c:         '',
        Investment_Vehicle_Type__c:  'Fund',
        Fund__c:                     null,
        Financial_Instrument__c:     null,
        Warehouse_Note__c:           null,
        Investor_Entity_ID__c: '',
        Investor_Entity__c:          '',
        Investor_Entity_Name__c:     '',
        Transaction_Type__c:         '',
        Amount__c:                   null,
        BDM__c:                      USER_ID,
        Switched_From__c:            null,
        Switch_Completed__c:         '',
        Money_Received_On__c:        '',
        Money_Received__c:           false,
        Comment__c:                  ''
    };

    @track selectedEntityName = '';
    @track entityNotFound     = false;
    @track isLoading          = false;
    @track hasError           = false;
    @track errorMessage       = '';

    _entityIdSearchTimeout;

    connectedCallback() {
        if (this.recordId) {
            this.isLoading = true;
            getTransactionById({ recordId: this.recordId })
                .then(data => {
                    this.isLoading = false;
                    if (data) {
                        this.record = {
                            Transaction_Date__c:         data.Transaction_Date__c         || '',
                            Investment_Vehicle_Type__c:  data.Investment_Vehicle_Type__c  || 'Fund',
                            Fund__c:                     data.Fund__c                     || null,
                            Financial_Instrument__c:     data.Financial_Instrument__c     || null,
                            Warehouse_Note__c:           data.Warehouse_Note__c           || null,
                            Investor_Entity_ID__c: data.Investor_Entity_ID__c || '',
                            Investor_Entity__c:          data.Investor_Entity__c          || '',
                            Investor_Entity_Name__c:     data.Investor_Entity_Name__c     || '',
                            Transaction_Type__c:         data.Transaction_Type__c         || '',
                            Amount__c:                   data.Amount__c                   || null,
                            BDM__c:                      data.BDM__c                      || USER_ID,
                            Switched_From__c:            data.Switched_From__c            || null,
                            Switch_Completed__c:         data.Switch_Completed__c         || '',
                            Money_Received_On__c:        data.Money_Received_On__c        || '',
                            Money_Received__c:           data.Money_Received__c           === true,
                            Comment__c:                  data.Comment__c                  || ''
                        };
                        this.selectedEntityName = data.Investor_Entity_Name__c || '';
                    }
                })
                .catch(err => {
                    this.isLoading    = false;
                    this.hasError     = true;
                    this.errorMessage = 'Could not load record: ' + (err.body?.message || err.message || 'Unknown error');
                });
        }
    }

    // --- Getters ---
    get modalTitle()         { return this.recordId ? 'Edit Transaction' : 'New Transaction'; }
    get saveLabel()          { return this.recordId ? 'Save Changes' : 'Create Transaction'; }
    get txTypeOptions()      { return TX_TYPE_OPTIONS; }
    get vehicleTypeOptions() { return VEHICLE_TYPE_OPTIONS; }
    get isSwitchType()       { return SWITCH_TYPES.has(this.record.Transaction_Type__c); }
    get isFundType()         { return !this.record.Investment_Vehicle_Type__c || this.record.Investment_Vehicle_Type__c === 'Fund'; }
    get isFIType()           { return this.record.Investment_Vehicle_Type__c === 'Financial Instrument'; }
    get isWNType()           { return this.record.Investment_Vehicle_Type__c === 'Warehouse Note'; }

    get vehicleId() {
        if (this.isFIType) return this.record.Financial_Instrument__c;
        if (this.isWNType) return this.record.Warehouse_Note__c;
        return this.record.Fund__c;
    }

    // Return undefined (not null) so the picker doesn't attempt to pre-load a null record ID
    get fundPickerValue()         { return this.record.Fund__c                 || undefined; }
    get fiPickerValue()           { return this.record.Financial_Instrument__c  || undefined; }
    get wnPickerValue()           { return this.record.Warehouse_Note__c        || undefined; }
    get switchedFromPickerValue() { return this.record.Switched_From__c         || undefined; }

    get isSaveDisabled() {
        return !this.record.Transaction_Date__c  ||
               !this.vehicleId                   ||
               !this.record.Investor_Entity__c   ||
               !this.record.Transaction_Type__c  ||
               !this.record.Amount__c            ||
               !this.record.BDM__c               ||
               (this.isSwitchType && !this.record.Switched_From__c);
    }

    get bdmPickerValue() { return this.record.BDM__c || undefined; }

    get showDerivedPreview() {
        return !!(this.selectedEntityName || this.record.Transaction_Date__c);
    }

    get derivedMonth() {
        if (!this.record.Transaction_Date__c) return '—';
        const d = new Date(this.record.Transaction_Date__c);
        return MONTH_NAMES[d.getMonth() + 1] || '—';
    }

    get derivedIntrafund() {
        if (!this.selectedEntityName) return '—';
        const name = this.selectedEntityName;
        return (name.includes('iPartners') && !name.includes('K+P')) ? 'Yes' : 'No';
    }

    // --- Record picker handlers ---
    // event.detail.recordId per official Salesforce docs (not event.detail.value)
    handleVehiclePickerChange(event) {
        const id = event.detail.recordId;
        if (this.isFundType) {
            this.record = { ...this.record, Fund__c: id };
        } else if (this.isFIType) {
            this.record = { ...this.record, Financial_Instrument__c: id };
        } else if (this.isWNType) {
            this.record = { ...this.record, Warehouse_Note__c: id };
        }
    }

    handleSwitchedFromPickerChange(event) {
        this.record = { ...this.record, Switched_From__c: event.detail.recordId };
    }

    handleBdmPickerChange(event) {
        this.record = { ...this.record, BDM__c: event.detail.recordId || null };
    }

    // --- Vehicle type ---
    handleVehicleTypeChange(event) {
        this.record = {
            ...this.record,
            Investment_Vehicle_Type__c: event.detail.value,
            Fund__c:                    null,
            Financial_Instrument__c:    null,
            Warehouse_Note__c:          null
        };
    }

    // --- Other handlers ---
    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const val   = event.detail.value !== undefined ? event.detail.value : event.detail.checked;
        this.record = { ...this.record, [field]: val };
    }

    handleTypeChange(event) {
        const txType = event.detail.value;
        this.record = {
            ...this.record,
            Transaction_Type__c: txType,
            Switched_From__c: SWITCH_TYPES.has(txType) ? this.record.Switched_From__c : null
        };
    }

    handleEntityIdChange(event) {
        const val = (event.detail.value || '').trim();
        this.entityNotFound = false;
        this.record = {
            ...this.record,
            Investor_Entity_ID__c: val,
            Investor_Entity__c:          '',
            Investor_Entity_Name__c:     ''
        };
        this.selectedEntityName = '';
        if (!val) return;

        clearTimeout(this._entityIdSearchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._entityIdSearchTimeout = setTimeout(() => {
            getEntityByExternalId({ entityId: val })
                .then(data => {
                    if (data) {
                        this.record = {
                            ...this.record,
                            Investor_Entity__c:      data.id,
                            Investor_Entity_Name__c: data.name
                        };
                        this.selectedEntityName = data.name;
                        this.entityNotFound     = false;
                    } else {
                        this.entityNotFound = true;
                    }
                })
                .catch(() => { this.entityNotFound = true; });
        }, 400);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick() {
        this.handleClose();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleSave() {
        this.isLoading = true;
        this.hasError  = false;

        const rec = { ...this.record };
        if (this.isFundType) {
            rec.Financial_Instrument__c = null;
            rec.Warehouse_Note__c       = null;
        } else if (this.isFIType) {
            rec.Fund__c           = null;
            rec.Warehouse_Note__c = null;
        } else if (this.isWNType) {
            rec.Fund__c                 = null;
            rec.Financial_Instrument__c = null;
        }
        if (this.recordId) rec.Id = this.recordId;

        saveTransaction({ record: rec })
            .then(result => {
                this.isLoading = false;
                if (result.saved) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: 'Transaction saved successfully.',
                        variant: 'success'
                    }));
                    this.dispatchEvent(new CustomEvent('save'));
                } else {
                    this.hasError     = true;
                    this.errorMessage = result.errors.join('; ');
                }
            })
            .catch(err => {
                this.isLoading    = false;
                this.hasError     = true;
                this.errorMessage = err.body?.message || 'An unexpected error occurred.';
            });
    }
}
