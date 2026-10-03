import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEntityByExternalId from '@salesforce/apex/FundTransactionController.getEntityByExternalId';
import saveBulk              from '@salesforce/apex/FundTransactionController.saveBulk';
import USER_ID               from '@salesforce/user/Id';

const MONTH_NAMES = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];

const SWITCH_TYPES    = new Set(['Fund Switch In', 'Fund Switch Out']);
const REQUIRED_FIELDS = ['Transaction_Date__c', 'Investor_Entity__c',
                          'Transaction_Type__c', 'Amount__c', 'BDM__c'];

let rowCounter = 0;

function makeRow() {
    return {
        key:                         String(++rowCounter),
        displayIndex:                rowCounter,
        Investment_Vehicle_Type__c:  'Fund',
        Transaction_Date__c:         '',
        Fund__c:                     '',
        Financial_Instrument__c:     '',
        Warehouse_Note__c:           '',
        Investor_Entity__c:          '',
        Investor_Entity_ID__c: '',
        Investor_Entity_Name__c:     '',
        Transaction_Type__c:         '',
        Amount__c:                   null,
        BDM__c:                      USER_ID,
        Switched_From__c:            '',
        Comment__c:                  '',
        entityDisplayName:           '',
        errors:                      {}
    };
}

export default class FundTransactionBulkEntry extends LightningElement {
    @track _rows          = [makeRow()];
    @track isSaving       = false;
    @track saveResult     = null;
    @track _saveAttempted = false;

    history = [];

    // --- Computed ---
    get saveLabel()   { return `Save ${this.rows.length} Row(s)`; }
    get noHistory()   { return this.history.length === 0; }
    get isSaveDisabled() { return this.isSaving || this.rows.length === 0; }

    get showValidationErrors() {
        return this._saveAttempted && this.hasErrors;
    }

    get hasErrors() {
        return this.rows.some(r => Object.keys(r.errors).length > 0 || !this.rowIsComplete(r));
    }

    get validationErrors() {
        const out = [];
        this.rows.forEach((r, i) => {
            const type       = r.Investment_Vehicle_Type__c || 'Fund';
            const hasVehicle = type === 'Financial Instrument' ? !!r.Financial_Instrument__c
                             : type === 'Warehouse Note'       ? !!r.Warehouse_Note__c
                             :                                   !!r.Fund__c;
            if (!hasVehicle) {
                out.push({ key: `${r.key}-vehicle`, message: `Row ${i + 1}: ${type} is required` });
            }
            REQUIRED_FIELDS.forEach(f => {
                if (!r[f]) {
                    if (f === 'Investor_Entity__c' && r.Investor_Entity_ID__c) {
                        out.push({ key: `${r.key}-${f}`, message: `Row ${i + 1}: Entity ID "${r.Investor_Entity_ID__c}" was not found` });
                    } else {
                        out.push({ key: `${r.key}-${f}`, message: `Row ${i + 1}: ${f.replace('__c','').replace(/_/g,' ')} is required` });
                    }
                }
            });
            if (SWITCH_TYPES.has(r.Transaction_Type__c) && !r.Switched_From__c) {
                out.push({ key: `${r.key}-switch`, message: `Row ${i + 1}: Switched From is required for switch transactions` });
            }
        });
        return out;
    }

    get saveResultClass()   { return 'save-result ' + (this.saveResult?.success ? 'save-result--success' : 'save-result--error'); }
    get saveResultIcon()    { return this.saveResult?.success ? 'utility:success' : 'utility:error'; }
    get saveResultMessage() { return this.saveResult?.message || ''; }

    rowIsComplete(r) {
        const required = [...REQUIRED_FIELDS];
        if (SWITCH_TYPES.has(r.Transaction_Type__c)) required.push('Switched_From__c');
        const type       = r.Investment_Vehicle_Type__c || 'Fund';
        const hasVehicle = type === 'Financial Instrument' ? !!r.Financial_Instrument__c
                         : type === 'Warehouse Note'       ? !!r.Warehouse_Note__c
                         :                                   !!r.Fund__c;
        return required.every(f => !!r[f]) && hasVehicle;
    }

    get decoratedRows() {
        return this._rows.map((r, i) => {
            const type       = r.Investment_Vehicle_Type__c || 'Fund';
            const hasVehicle = type === 'Financial Instrument' ? !!r.Financial_Instrument__c
                             : type === 'Warehouse Note'       ? !!r.Warehouse_Note__c
                             :                                   !!r.Fund__c;
            return {
                ...r,
                displayIndex:     i + 1,
                isSwitchType:     SWITCH_TYPES.has(r.Transaction_Type__c),
                isFundTarget:     type === 'Fund',
                isFITarget:       type === 'Financial Instrument',
                isWNTarget:       type === 'Warehouse Note',
                entityUsed:       r.entityDisplayName || (r.Investor_Entity_ID__c && !r.Investor_Entity__c ? 'Not found' : '—'),
                month:            this.deriveMonth(r.Transaction_Date__c),
                intrafundLabel:   this.deriveIntrafund(r.entityDisplayName) ? 'Yes' : 'No',
                intrafundClass:   'derived-cell' + (this.deriveIntrafund(r.entityDisplayName) ? ' derived-cell--intrafund' : ''),
                rowClass:         'grid-row' + (Object.keys(r.errors).length ? ' grid-row--error' : ''),
                dateCellClass:    'col-date'    + (r.errors.Transaction_Date__c ? ' cell--error' : ''),
                vehicleCellClass: 'col-vehicle' + (!hasVehicle && this._saveAttempted ? ' cell--error' : ''),
                targetCellClass:  'col-target'  + (!hasVehicle && this._saveAttempted ? ' cell--error' : ''),
                entityCellClass:  'col-entity'  + (r.Investor_Entity_ID__c && !r.Investor_Entity__c ? ' cell--error' : ''),
                typeCellClass:    'col-type'    + (r.errors.Transaction_Type__c ? ' cell--error' : ''),
                amountCellClass:  'col-amount'  + (r.errors.Amount__c ? ' cell--error' : ''),
                bdmCellClass:     'col-bdm'     + (r.errors.BDM__c ? ' cell--error' : ''),
                bdmPickerValue:   r.BDM__c || undefined,
                // Pass current IDs to pickers — undefined (not null) prevents the picker spinning on empty rows
                fundPickerValue:  r.Fund__c                || undefined,
                fiPickerValue:    r.Financial_Instrument__c || undefined,
                wnPickerValue:    r.Warehouse_Note__c       || undefined,
                switchPickerValue: r.Switched_From__c      || undefined
            };
        });
    }

    get rows() { return this._rows; }

    deriveMonth(dateStr) {
        if (!dateStr) return '—';
        const d = new Date(dateStr);
        return MONTH_NAMES[d.getMonth() + 1] || '—';
    }

    deriveIntrafund(name) {
        if (!name) return false;
        return name.includes('iPartners') && !name.includes('K+P');
    }

    // --- Cell change (date, type, amount, comment) ---
    handleCellChange(event) {
        const key   = event.currentTarget.dataset.row;
        const field = event.currentTarget.dataset.field;
        const val   = event.target.value;
        this.pushHistory();
        this.updateRow(key, { [field]: val });
    }

    // --- Vehicle type change ---
    handleVehicleTypeChange(event) {
        const key  = event.currentTarget.dataset.row;
        const type = event.target.value;
        this.pushHistory();
        this.updateRow(key, {
            Investment_Vehicle_Type__c: type,
            Fund__c:                    '',
            Financial_Instrument__c:    '',
            Warehouse_Note__c:          ''
        });
    }

    // --- lightning-record-picker handlers ---
    // event.detail.recordId per official Salesforce docs
    handleVehiclePickerChange(event) {
        const key  = event.currentTarget.dataset.row;
        const id   = event.detail.recordId;
        const row  = this._rows.find(r => r.key === key);
        if (!row) return;
        const type = row.Investment_Vehicle_Type__c || 'Fund';
        const updates = {};
        if (type === 'Financial Instrument') {
            updates.Financial_Instrument__c = id || '';
        } else if (type === 'Warehouse Note') {
            updates.Warehouse_Note__c = id || '';
        } else {
            updates.Fund__c = id || '';
        }
        this.pushHistory();
        this.updateRow(key, updates);
    }

    handleSwitchedFromPickerChange(event) {
        const key = event.currentTarget.dataset.row;
        const id  = event.detail.recordId;
        this.pushHistory();
        this.updateRow(key, { Switched_From__c: id || '' });
    }

    handleBdmPickerChange(event) {
        const key = event.currentTarget.dataset.row;
        const id  = event.detail.recordId;
        this.pushHistory();
        this.updateRow(key, { BDM__c: id || '' });
    }

    // Scroll the focused record-picker to the centre of the viewport so the
    // dropdown has room to open below without going off-screen.
    handlePickerFocus(event) {
        if (event.target?.tagName?.toLowerCase() !== 'lightning-record-picker') return;
        const el = event.target;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            el.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }, 0);
    }

    // --- Keyboard navigation ---
    handleKeyDown(event) {
        const key = event.currentTarget.dataset.row;
        const col = parseInt(event.currentTarget.dataset.col, 10);

        if (event.key === 'Tab') {
            event.preventDefault();
            const rowIdx = this._rows.findIndex(r => r.key === key);
            const maxCol = 8;
            let nextCol  = event.shiftKey ? col - 1 : col + 1;
            let nextRow  = rowIdx;

            if (nextCol > maxCol) { nextCol = 0; nextRow++; }
            if (nextCol < 0)      { nextCol = maxCol; nextRow--; }
            if (nextRow < 0) return;
            if (nextRow >= this._rows.length) {
                this._rows = [...this._rows, makeRow()];
            }
            this.focusCell(this._rows[nextRow].key, nextCol);
        }

        if (event.key === 'Enter') {
            event.preventDefault();
            const rowIdx  = this._rows.findIndex(r => r.key === key);
            const nextRow = rowIdx + 1;
            if (nextRow >= this._rows.length) {
                this._rows = [...this._rows, makeRow()];
            }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.focusCell(this._rows[Math.min(nextRow, this._rows.length - 1)].key, col);
            }, 0);
        }
    }

    focusCell(rowKey, col) {
        const el = this.template.querySelector(`[data-row="${rowKey}"][data-col="${col}"]`);
        if (el) el.focus();
    }

    // --- Entity ID lookup ---
    handleEntityIdInput(event) {
        const key = event.currentTarget.dataset.row;
        const val = (event.target.value || '').trim();

        this.updateRow(key, {
            Investor_Entity__c:          '',
            entityDisplayName:           val ? '...' : '',
            Investor_Entity_ID__c: '',
            Investor_Entity_Name__c:     ''
        });

        clearTimeout(this._entitySearchTimeout);
        if (!val) return;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._entitySearchTimeout = setTimeout(() => {
            getEntityByExternalId({ entityId: val })
                .then(data => {
                    if (data) {
                        this.pushHistory();
                        this.updateRow(key, {
                            Investor_Entity__c:          data.id,
                            entityDisplayName:           data.name,
                            Investor_Entity_ID__c: val,
                            Investor_Entity_Name__c:     data.name
                        });
                    } else {
                        this.updateRow(key, {
                            Investor_Entity__c:          '',
                            entityDisplayName:           'Not found',
                            Investor_Entity_ID__c: val,
                            Investor_Entity_Name__c:     ''
                        });
                    }
                })
                .catch(() => {
                    this.updateRow(key, {
                        Investor_Entity__c:          '',
                        entityDisplayName:           'Not found',
                        Investor_Entity_ID__c: val,
                        Investor_Entity_Name__c:     ''
                    });
                });
        }, 500);
    }

    // --- Fill-down ---
    fillDown(fromKey) {
        const fromIdx = this._rows.findIndex(r => r.key === fromKey);
        if (fromIdx < 0) return;
        const source = this._rows[fromIdx];
        this.pushHistory();
        this._rows = this._rows.map((r, i) => {
            if (i <= fromIdx) return r;
            return {
                ...r,
                Investment_Vehicle_Type__c: source.Investment_Vehicle_Type__c,
                BDM__c:                     source.BDM__c,
                Transaction_Type__c:        source.Transaction_Type__c
            };
        });
    }

    // --- CRUD ---
    addRow() {
        this.pushHistory();
        this._rows = [...this._rows, makeRow()];
    }

    deleteRow(event) {
        const key = event.currentTarget.dataset.row;
        if (this._rows.length === 1) return;
        this.pushHistory();
        this._rows = this._rows.filter(r => r.key !== key);
    }

    clearAll() {
        this.pushHistory();
        rowCounter          = 0;
        this._rows          = [makeRow()];
        this.saveResult     = null;
        this._saveAttempted = false;
    }

    // --- Undo ---
    pushHistory() {
        this.history = [...this.history.slice(-19), JSON.parse(JSON.stringify(this._rows))];
    }

    undo() {
        if (!this.history.length) return;
        const prev = this.history.pop();
        this._rows = prev;
    }

    // --- Save ---
    handleSave() {
        if (this.isSaveDisabled) return;
        if (this.hasErrors) {
            this._saveAttempted = true;
            return;
        }
        this._saveAttempted = false;
        this.isSaving   = true;
        this.saveResult = null;

        const toSave = this._rows
            .filter(r => this.rowIsComplete(r))
            .map(r => {
                const type = r.Investment_Vehicle_Type__c || 'Fund';
                return {
                    Investment_Vehicle_Type__c:  type,
                    Transaction_Date__c:         r.Transaction_Date__c,
                    Fund__c:                     type === 'Fund'                 ? (r.Fund__c || null)                 : null,
                    Financial_Instrument__c:     type === 'Financial Instrument' ? (r.Financial_Instrument__c || null) : null,
                    Warehouse_Note__c:           type === 'Warehouse Note'       ? (r.Warehouse_Note__c || null)       : null,
                    Investor_Entity__c:          r.Investor_Entity__c,
                    Investor_Entity_ID__c: r.Investor_Entity_ID__c || '',
                    Investor_Entity_Name__c:     r.Investor_Entity_Name__c     || '',
                    Transaction_Type__c:         r.Transaction_Type__c,
                    Amount__c:                   parseFloat(r.Amount__c),
                    BDM__c:                      r.BDM__c,
                    Switched_From__c:            r.Switched_From__c    || null,
                    Money_Received_On__c:        r.Money_Received_On__c || null,
                    Switch_Completed__c:         r.Switch_Completed__c || null,
                    Comment__c:                  r.Comment__c          || null
                };
            });

        saveBulk({ records: toSave })
            .then(result => {
                this.isSaving = false;
                if (result.errors && result.errors.length) {
                    this.saveResult = {
                        success: false,
                        message: `${result.saved} saved. ${result.errors.length} error(s): ${result.errors[0]}`
                    };
                } else {
                    this.saveResult = {
                        success: true,
                        message: `${result.saved} transaction(s) saved successfully.`
                    };
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Transactions Saved',
                        message: `${result.saved} transaction(s) saved.`,
                        variant: 'success'
                    }));
                    rowCounter          = 0;
                    this._rows          = [makeRow()];
                    this._saveAttempted = false;
                }
            })
            .catch(err => {
                this.isSaving = false;
                this.saveResult = {
                    success: false,
                    message: err.body?.message || 'An unexpected error occurred.'
                };
            });
    }

    // --- Helpers ---
    updateRow(key, changes) {
        this._rows = this._rows.map(r => r.key === key ? { ...r, ...changes } : r);
    }
}
