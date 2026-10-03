import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasImportPermission from '@salesforce/customPermission/Secondary_Trading_Import';
import getContentVersion from '@salesforce/apex/SecondaryTradingImportController.getContentVersion';
import parseCSV         from '@salesforce/apex/SecondaryTradingImportController.parseCSV';
import importRows       from '@salesforce/apex/SecondaryTradingImportController.importRows';

// ─── Constants ────────────────────────────────────────────────────────────────

const STEPS = Object.freeze({ UPLOAD: 'upload', PREVIEW: 'preview', RESULT: 'result' });

// lightning-datatable column definitions.
// cellAttributes.class uses a field name from row data so each row can have
// its own colour applied to the Status and Validation columns.
const COLUMNS = [
    {
        label: '#',
        fieldName: 'rowNumber',
        type: 'number',
        initialWidth: 58,
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Status',
        fieldName: 'statusDisplay',
        type: 'text',
        initialWidth: 80,
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    { label: 'Deal Code',              fieldName: 'deal',                   type: 'text', initialWidth: 110 },
    { label: 'Trading Name',           fieldName: 'tradingName',            type: 'text' },
    { label: 'Offer Initiated By',     fieldName: 'offerInitiatedBy',       type: 'text' },
    { label: 'Is Workout?',            fieldName: 'isWorkout',              type: 'text', initialWidth: 100 },
    { label: 'Units',                  fieldName: 'units',                  type: 'number', initialWidth: 90 },
    { label: 'Buyer',                  fieldName: 'buyer',                  type: 'text' },
    { label: 'Seller',                 fieldName: 'seller',                 type: 'text' },
    { label: 'Syn. Comms Required',    fieldName: 'syndicateCommsRequired', type: 'text', initialWidth: 160 },
    { label: 'Workout',                fieldName: 'workout',                type: 'text' },
    { label: 'Unit Price',             fieldName: 'unitPrice',              type: 'number', initialWidth: 110 },
    { label: 'Effective Date',         fieldName: 'effectiveDate',          type: 'text', initialWidth: 120 },
    {
        label: 'Validation',
        fieldName: 'errorMessage',
        type: 'text',
        wrapText: true,
        initialWidth: 260,
        cellAttributes: { class: { fieldName: 'validationClass' } }
    }
];

const TEMPLATE_CSV =
    'Deal Code,Secondary Trading Name,Offer Initiated By,Is Workout/Distressed,Units,Buyer,Seller,Syndicate Comms Required,Workout,Unit Price,Effective Date\n' +
    'ABC001,Alpha Trade,Investor Offer,No,100,Syndicate/Investor,ICIF01-Core Income Fund,No,,95.50,25-07-2026\n' +
    'ABC002,Beta Trade,Funds Bid,Yes,250,ICIF02-Short Term Income Fund,Syndicate/Investor,Yes,Workout Record Name,98.00,01-08-2026\n' +
    'ABC003,Gamma Trade,Funds / Funds,No,75,ICIF01-Core Income Fund,ICIF02-Short Term Income Fund,No,,100.00,10-08-2026\n';

// ─── Component ────────────────────────────────────────────────────────────────

export default class SecondaryTradingImport extends LightningElement {

    // @track only needed for objects/arrays mutated in place;
    // primitives re-render automatically, but explicit tracking avoids surprises.
    @track step         = STEPS.UPLOAD;
    @track previewRows  = [];
    @track importResult = null;
    @track isLoading    = false;
    @track errorMessage = null;
    @track isDragging   = false;

    columns = COLUMNS;

    // ─── Permissions ──────────────────────────────────────────────────────────

    get hasPermission() { return hasImportPermission; }

    // ─── Step state ───────────────────────────────────────────────────────────

    get isStepUpload()  { return this.step === STEPS.UPLOAD; }
    get isStepPreview() { return this.step === STEPS.PREVIEW; }
    get isStepResult()  { return this.step === STEPS.RESULT; }

    // ─── Step indicator CSS classes ───────────────────────────────────────────

    get step1Class() {
        if (this.step === STEPS.UPLOAD)   return 'step-indicator__item step-indicator__item--active';
        return 'step-indicator__item step-indicator__item--done';
    }
    get step2Class() {
        if (this.step === STEPS.UPLOAD)   return 'step-indicator__item step-indicator__item--pending';
        if (this.step === STEPS.PREVIEW)  return 'step-indicator__item step-indicator__item--active';
        return 'step-indicator__item step-indicator__item--done';
    }
    get step3Class() {
        if (this.step === STEPS.RESULT)   return 'step-indicator__item step-indicator__item--active';
        return 'step-indicator__item step-indicator__item--pending';
    }
    get connectorClass1() {
        return this.step !== STEPS.UPLOAD ? 'step-connector step-connector--done' : 'step-connector';
    }
    get connectorClass2() {
        return this.step === STEPS.RESULT ? 'step-connector step-connector--done' : 'step-connector';
    }
    get step1Done() { return this.step !== STEPS.UPLOAD; }
    get step2Done() { return this.step === STEPS.RESULT; }

    // ─── Preview computed values ──────────────────────────────────────────────

    get validCount()  { return this.previewRows.filter(r => !r.hasError).length; }
    get errorCount()  { return this.previewRows.filter(r =>  r.hasError).length; }
    get totalCount()  { return this.previewRows.length; }
    get hasErrors()   { return this.errorCount > 0; }
    get noValidRows() { return this.validCount === 0; }

    get importButtonLabel() {
        const n = this.validCount;
        return `Import ${n} Record${n !== 1 ? 's' : ''}`;
    }

    get errorPluralS()  { return this.errorCount !== 1 ? 's' : ''; }
    get validPluralS()  { return this.validCount  !== 1 ? 's' : ''; }

    // ─── Result computed values ───────────────────────────────────────────────

    get importSucceeded()  { return this.importResult && this.importResult.successCount > 0; }
    get importAllFailed()  {
        return this.importResult
            && this.importResult.successCount === 0
            && this.importResult.failureCount > 0;
    }
    get hasImportErrors()  {
        return this.importResult
            && this.importResult.errors
            && this.importResult.errors.length > 0;
    }
    get successPluralS()   { return this.importResult && this.importResult.successCount !== 1 ? 's' : ''; }
    get failPluralS()      { return this.importResult && this.importResult.failureCount !== 1 ? 's' : ''; }

    // ─── Drop zone CSS ────────────────────────────────────────────────────────

    get dropZoneClass() {
        return this.isDragging ? 'drop-zone drop-zone--active' : 'drop-zone';
    }

    // ─── Drag-and-drop handlers ───────────────────────────────────────────────

    handleDragOver(event) {
        event.preventDefault();
        this.isDragging = true;
    }

    handleDragLeave() {
        this.isDragging = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragging = false;
        const files = event.dataTransfer && event.dataTransfer.files;
        if (!files || files.length === 0) return;
        const file = files[0];
        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.errorMessage = 'Please drop a .csv file.';
            return;
        }
        this._readFileAndParse(file);
    }

    // ─── lightning-file-upload handler ───────────────────────────────────────

    handleFileUpload(event) {
        const files = event.detail && event.detail.files;
        if (!files || files.length === 0) return;
        const contentVersionId = files[0].contentVersionId;
        this.isLoading    = true;
        this.errorMessage = null;

        getContentVersion({ contentVersionId })
            .then(csvContent => parseCSV({ csvContent }))
            .then(rows => this._applyParsedRows(rows))
            .catch(err => this._handleError(err));
    }

    // ─── Preview actions ──────────────────────────────────────────────────────

    handleBack() {
        this.step         = STEPS.UPLOAD;
        this.previewRows  = [];
        this.errorMessage = null;
    }

    handleConfirmImport() {
        if (this.noValidRows) return;
        // Serialize to JSON string before sending to Apex.
        // Passing typed inner-class lists directly from LWC is unreliable —
        // Apex receives empty objects because LWC proxy wrappers don't serialize
        // correctly through the automatic parameter binding layer.
        // Passing a JSON string and deserializing explicitly in Apex is the
        // reliable pattern for this scenario.
        const validRows = this.previewRows.filter(r => !r.hasError);
        const rowsJson  = JSON.stringify(validRows);
        this.step         = STEPS.RESULT;
        this.isLoading    = true;
        this.errorMessage = null;

        importRows({ rowsJson })
            .then(result => {
                this.importResult = result;
                this.isLoading    = false;
                if (result.successCount > 0) {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Import Complete',
                        message: `${result.successCount} record${result.successCount !== 1 ? 's' : ''} imported successfully.`,
                        variant: 'success'
                    }));
                }
            })
            .catch(err => this._handleError(err));
    }

    // ─── Result actions ───────────────────────────────────────────────────────

    handleReset() {
        this.step         = STEPS.UPLOAD;
        this.previewRows  = [];
        this.importResult = null;
        this.errorMessage = null;
        this.isLoading    = false;
    }

    // ─── Template download ────────────────────────────────────────────────────

    handleDownloadTemplate() {
        const a    = document.createElement('a');
        a.href     = 'data:text/csv;charset=utf-8,' + encodeURIComponent(TEMPLATE_CSV);
        a.download = 'SecondaryTrading_Import_Template.csv';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    // ─── Error banner ─────────────────────────────────────────────────────────

    clearError() {
        this.errorMessage = null;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    /**
     * Reads a File object directly via FileReader (used by the drag-and-drop path).
     * The text content is sent straight to the Apex parseCSV method — no ContentVersion
     * is created for drag-and-drop, keeping the logic DRY since parseCSV accepts a string.
     */
    _readFileAndParse(file) {
        this.isLoading    = true;
        this.errorMessage = null;
        const reader      = new FileReader();

        reader.onload = (e) => {
            parseCSV({ csvContent: e.target.result })
                .then(rows => this._applyParsedRows(rows))
                .catch(err => this._handleError(err));
        };
        reader.onerror = () => {
            this.isLoading    = false;
            this.errorMessage = 'Could not read the file. Please try again.';
        };
        reader.readAsText(file);
    }

    /**
     * Decorates parsed Apex rows with UI display fields then moves to Preview step.
     * statusDisplay / statusClass drive the coloured Status column.
     * validationClass colours the Validation (error message) column red for problem rows.
     */
    _applyParsedRows(rows) {
        // Explicitly map each field rather than spreading — LWC reactive proxies
        // returned from Apex do not reliably copy via the spread operator, which
        // would silently drop all property values when the row is later sent back
        // to Apex in importRows.
        this.previewRows = rows.map(r => ({
            rowNumber:              r.rowNumber,
            deal:                   r.deal,
            tradingName:            r.tradingName,
            offerInitiatedBy:       r.offerInitiatedBy,
            isWorkout:              r.isWorkout,
            units:                  r.units,
            buyer:                  r.buyer,
            seller:                 r.seller,
            syndicateCommsRequired: r.syndicateCommsRequired,
            workout:                r.workout,
            unitPrice:              r.unitPrice,
            effectiveDate:          r.effectiveDate,
            hasError:               r.hasError,
            errorMessage:           r.errorMessage,
            statusDisplay:          r.hasError ? '✗ Error' : '✓ Valid',
            statusClass:            r.hasError ? 'cell-error' : 'cell-valid',
            validationClass:        r.hasError ? 'cell-error' : ''
        }));
        this.step      = STEPS.PREVIEW;
        this.isLoading = false;

        if (this.previewRows.length === 0) {
            this.errorMessage = 'No data rows were found in the file.';
            this.step = STEPS.UPLOAD;
        }
    }

    _handleError(err) {
        this.isLoading    = false;
        this.errorMessage = (err.body && err.body.message) ? err.body.message : err.message;
        // If we were mid-import and hit an unexpected error, stay on result so
        // the partial result (if any) plus the error banner are both visible.
        // For upload/parse errors, go back to upload so user can try again.
        if (this.step === STEPS.RESULT && !this.importResult) {
            this.step = STEPS.UPLOAD;
        }
    }
}
