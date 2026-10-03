import { LightningElement, track } from 'lwc';
import { ShowToastEvent }  from 'lightning/platformShowToastEvent';
import hasImportPerm       from '@salesforce/customPermission/Fund_Transaction_Importer';
import importCSVRaw        from '@salesforce/apex/FundTransactionController.importCSVRaw';

const STEP = { UPLOAD: 1, PREVIEW: 2, RESULT: 3 };

const TEMPLATE_HEADERS = [
    'Transaction_Date', 'Fund_Name', 'Investor_Entity_ID', 'Transaction_Type',
    'Amount', 'BDM_Username', 'Switched_From_Fund_Name', 'Money_Received',
    'Money_Received_On', 'Switch_Completed', 'Comment', 'Financial_Instrument_Name', 'Warehouse_Note_Name'
];

// JS mirror of Apex parseDateDMY (SecondaryTradingImportController logic)
const MONTH_MAP = {
    jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3,
    apr: 4, april: 4, may: 5, jun: 6, june: 6, jul: 7, july: 7,
    aug: 8, august: 8, sep: 9, september: 9, oct: 10, october: 10,
    nov: 11, november: 11, dec: 12, december: 12
};

function parseDateDMY(s) {
    if (!s || !s.trim()) throw new Error('Date is blank');
    const norm  = s.trim().replace(/\//g, '-');
    const parts = norm.split('-');
    if (parts.length !== 3) throw new Error('Cannot parse date: ' + s);
    const p0 = parts[0].trim(), p1 = parts[1].trim(), p2 = parts[2].trim();
    let d, m, y;
    if (MONTH_MAP[p1.toLowerCase()] !== undefined) {
        d = parseInt(p0, 10); m = MONTH_MAP[p1.toLowerCase()]; y = parseInt(p2, 10);
    } else if (p0.length === 4) {
        y = parseInt(p0, 10); m = parseInt(p1, 10); d = parseInt(p2, 10);
    } else {
        d = parseInt(p0, 10); m = parseInt(p1, 10); y = parseInt(p2, 10);
    }
    if (y < 100) y += 2000;
    if (isNaN(d) || isNaN(m) || isNaN(y) || d < 1 || d > 31 || m < 1 || m > 12 || y < 1900 || y > 2200) {
        throw new Error('Invalid date values in: ' + s);
    }
}

const DATE_FMT_HINT = 'use DD/MM/YYYY, D-Mon-YY or D-Month-YYYY (e.g. 25/07/2026, 25-Jul-26)';

function validateRow(row) {
    const errors = [];

    // Date fields
    if (row.Transaction_Date__c) {
        try { parseDateDMY(row.Transaction_Date__c); }
        catch (_) { errors.push('Transaction Date: invalid format — ' + DATE_FMT_HINT); }
    }
    if (row.Money_Received_On__c) {
        try { parseDateDMY(row.Money_Received_On__c); }
        catch (_) { errors.push('Money Received On: invalid format — ' + DATE_FMT_HINT); }
    }
    if (row.Switch_Completed__c) {
        try { parseDateDMY(row.Switch_Completed__c); }
        catch (_) { errors.push('Switch Completed: invalid format — ' + DATE_FMT_HINT); }
    }

    // Boolean: Money Received must be Yes or No
    if (row.Money_Received__c && row.Money_Received__c.trim()) {
        const mr = row.Money_Received__c.toLowerCase().trim();
        if (mr !== 'yes' && mr !== 'no') {
            errors.push('Money Received must be Yes or No');
        }
    }

    // Vehicle type: exactly one of Fund, FI, Warehouse Note
    const vehicles = [row.fundName, row.fiName, row.warehouseName].filter(v => v && v.trim());
    if (vehicles.length === 0) {
        errors.push('At least one vehicle must be specified: Fund Name, Financial Instrument Name, or Warehouse Note Name');
    } else if (vehicles.length > 1) {
        errors.push('Only one vehicle should be specified: Fund Name, Financial Instrument Name, or Warehouse Note Name');
    }

    // Switch fields only valid for Fund Switch In / Out
    const isSwitchType = row.Transaction_Type__c === 'Fund Switch In' || row.Transaction_Type__c === 'Fund Switch Out';
    if (!isSwitchType) {
        if (row.Switch_Completed__c && row.Switch_Completed__c.trim()) {
            errors.push('Switch Completed is only valid for Fund Switch In / Fund Switch Out');
        }
        if (row.switchedFromFund && row.switchedFromFund.trim()) {
            errors.push('Switched From Fund Name is only valid for Fund Switch In / Fund Switch Out');
        }
    }

    return errors;
}

function parseCsvLine(line) {
    const fields = [];
    let cur = '';
    let inQuote = false;
    for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"') {
            if (inQuote && line[i + 1] === '"') { cur += '"'; i++; }
            else { inQuote = !inQuote; }
        } else if (ch === ',' && !inQuote) {
            fields.push(cur.trim());
            cur = '';
        } else {
            cur += ch;
        }
    }
    fields.push(cur.trim());
    return fields;
}

function normalise(str) {
    return str.toLowerCase().replace(/[^a-z0-9]/g, '_');
}

export default class FundTransactionImport extends LightningElement {
    @track step         = STEP.UPLOAD;
    @track previewRows  = [];
    @track importResult = null;
    @track isImporting  = false;
    @track isDragOver   = false;

    fileName             = '';
    parsedRecords        = [];
    _selectedRowIndices  = new Set();

    get hasImportPerm() { return hasImportPerm; }

    get isStep1() { return this.step === STEP.UPLOAD; }
    get isStep2() { return this.step === STEP.PREVIEW; }
    get isStep3() { return this.step === STEP.RESULT; }

    get step1Class() { return 'step-item' + (this.step >= 1 ? ' step-item--active' : ''); }
    get step2Class() { return 'step-item' + (this.step >= 2 ? ' step-item--active' : ''); }
    get step3Class() { return 'step-item' + (this.step === 3 ? ' step-item--active' : ''); }

    get uploadZoneClass() {
        return 'upload-zone' + (this.isDragOver ? ' upload-zone--dragover' : '');
    }

    get validCount() {
        return this.previewRows.filter(r => !r.hasValidationError).length;
    }

    get confirmLabel() {
        return `Import ${this.validCount} Valid Record(s)`;
    }

    get resolutionErrorCount() {
        return this.importResult?.resolutionErrors?.length || 0;
    }

    get resultIcon() {
        return this.importResult?.imported > 0 ? 'utility:success' : 'utility:warning';
    }

    get resultIconClass() {
        return this.importResult?.imported > 0 ? 'result-icon result-icon--success' : 'result-icon result-icon--warn';
    }

    get resultTitle() {
        if (this.importResult?.imported > 0) {
            return `${this.importResult.imported} transaction(s) imported successfully`;
        }
        if (this.resolutionErrorCount > 0) {
            return `Import failed — ${this.resolutionErrorCount} row(s) could not be resolved`;
        }
        return 'Import complete — no new records were inserted';
    }

    // --- Upload ---
    handleUploadClick() {
        this.template.querySelector('input[type="file"]').click();
    }

    handleDragOver(event) {
        event.preventDefault();
        this.isDragOver = true;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragOver = false;
        const file = event.dataTransfer.files[0];
        if (file) this.processFile(file);
    }

    handleFileSelect(event) {
        const file = event.target.files[0];
        if (file) this.processFile(file);
    }

    processFile(file) {
        if (!file.name.endsWith('.csv')) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invalid File',
                message: 'Please upload a .csv file.',
                variant: 'error'
            }));
            return;
        }
        this.fileName = file.name;
        const reader  = new FileReader();
        reader.onload = (e) => {
            const rows = this.parseCSV(e.target.result);
            this.parsedRecords = rows;
            this.previewRows   = rows.map((r, i) => ({
                ...r,
                index:             i,
                displayIndex:      i + 1,
                validationMessage: r.validationErrors.join('; '),
                formattedAmount:   r.Amount__c
                    ? new Intl.NumberFormat('en-AU', { style: 'currency', currency: 'AUD' }).format(r.Amount__c)
                    : '—'
            }));
            this.step = STEP.PREVIEW;
        };
        reader.readAsText(file);
    }

    parseCSV(text) {
        const lines = text.trim().split(/\r?\n/);
        if (lines.length < 2) return [];

        const headers = parseCsvLine(lines[0]).map(h => normalise(h));

        function getVal(name, vals) {
            const idx = headers.indexOf(normalise(name));
            return idx >= 0 ? (vals[idx] || '') : '';
        }

        const records = [];
        for (let i = 1; i < lines.length; i++) {
            const vals = parseCsvLine(lines[i]);
            if (vals.every(v => !v)) continue;

            const record = {
                Transaction_Date__c:  getVal('Transaction_Date', vals),
                fundName:             getVal('Fund_Name', vals),
                entityId:             getVal('Investor_Entity_ID', vals),
                Transaction_Type__c:  getVal('Transaction_Type', vals),
                Amount__c:            parseFloat(getVal('Amount', vals)) || null,
                bdmUsername:          getVal('BDM_Username', vals),
                switchedFromFund:     getVal('Switched_From_Fund_Name', vals),
                Money_Received__c:    getVal('Money_Received', vals),
                Money_Received_On__c: getVal('Money_Received_On', vals),
                Switch_Completed__c:  getVal('Switch_Completed', vals),
                Comment__c:           getVal('Comment', vals),
                fiName:               getVal('Financial_Instrument_Name', vals),
                warehouseName:        getVal('Warehouse_Note_Name', vals)
            };
            const validationErrors    = validateRow(record);
            record.validationErrors   = validationErrors;
            record.hasValidationError = validationErrors.length > 0;
            records.push(record);
        }
        return records;
    }

    // --- Template download ---
    handleDownloadTemplate() {
        const csv  = TEMPLATE_HEADERS.join(',') + '\n';
        const a    = document.createElement('a');
        a.href     = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = 'FundTransaction_Import_Template.csv';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    // --- Results download ---
    handleDownloadResults() {
        const errorMap = {};
        (this.importResult?.resolutionErrors || []).forEach(re => {
            errorMap[re.rowIndex] = re.errors.join('; ');
        });

        function csvCell(v) {
            const s = String(v ?? '');
            return s.includes(',') || s.includes('"') || s.includes('\n')
                ? `"${s.replace(/"/g, '""')}"` : s;
        }

        const header = [...TEMPLATE_HEADERS, 'Import_Status'].map(csvCell).join(',');

        const dataRows = this.previewRows.map(r => {
            let status;
            if (r.hasValidationError) {
                status = r.validationMessage;
            } else if (errorMap[r.index] !== undefined) {
                status = errorMap[r.index];
            } else {
                status = 'Success';
            }

            return [
                r.Transaction_Date__c,
                r.fundName,
                r.entityId,
                r.Transaction_Type__c,
                r.Amount__c != null ? r.Amount__c : '',
                r.bdmUsername,
                r.switchedFromFund,
                r.Money_Received__c,
                r.Money_Received_On__c,
                r.Switch_Completed__c,
                r.Comment__c,
                r.fiName,
                r.warehouseName,
                status
            ].map(csvCell).join(',');
        });

        const csv      = [header, ...dataRows].join('\n');
        const baseName = this.fileName.replace(/\.csv$/i, '');
        const a        = document.createElement('a');
        a.href         = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download     = `${baseName}_results.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    handleBack() {
        this.step        = STEP.UPLOAD;
        this.previewRows = [];
    }

    handleConfirmImport() {
        const selectedRows = this.previewRows
            .filter(r => !r.hasValidationError)
            .map(r => ({
                transactionDate:      r.Transaction_Date__c || '',
                fundName:             r.fundName            || '',
                entityId:             r.entityId            || '',
                transactionType:      r.Transaction_Type__c || '',
                amount:               r.Amount__c,
                bdmUsername:          r.bdmUsername         || '',
                switchedFromFundName: r.switchedFromFund    || '',
                moneyReceivedBoolean: r.Money_Received__c    || '',
                moneyReceivedOn:      r.Money_Received_On__c || '',
                switchCompleted:      r.Switch_Completed__c  || '',
                comment:              r.Comment__c          || '',
                fiName:               r.fiName              || '',
                warehouseName:        r.warehouseName       || '',
                rowIndex:             r.index
            }));

        if (!selectedRows.length) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Nothing to Import',
                message: 'No valid rows to import. Fix validation errors and re-upload.',
                variant: 'warning'
            }));
            return;
        }

        this._selectedRowIndices = new Set(selectedRows.map(r => r.rowIndex));
        this.isImporting = true;

        importCSVRaw({ rows: selectedRows, sourceFileName: this.fileName })
            .then(result => {
                this.isImporting  = false;
                this.importResult = {
                    imported:         result.imported,
                    resolutionErrors: (result.resolutionErrors || []).map(re => ({
                        ...re,
                        displayRowIndex: re.rowIndex + 1
                    }))
                };
                this.step = STEP.RESULT;
            })
            .catch(err => {
                this.isImporting = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Import Failed',
                    message: err.body?.message || 'An unexpected error occurred.',
                    variant: 'error'
                }));
            });
    }

    handleReset() {
        this.step                = STEP.UPLOAD;
        this.previewRows         = [];
        this.importResult        = null;
        this.fileName            = '';
        this._selectedRowIndices = new Set();
    }

    handleViewTransactions() {
        this.dispatchEvent(new CustomEvent('refresh'));
    }
}
