import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTransactions    from '@salesforce/apex/FundTransactionController.getTransactions';
import getFunds           from '@salesforce/apex/FundTransactionController.getFunds';
import hasFullAccess      from '@salesforce/customPermission/Full_Transaction_Access';

const PAGE_SIZE = 50;

const TX_TYPE_OPTIONS = [
    { label: 'New Application', value: 'New Application' },
    { label: 'Fund Switch In',  value: 'Fund Switch In' },
    { label: 'Fund Redemption', value: 'Fund Redemption' },
    { label: 'Fund Switch Out', value: 'Fund Switch Out' }
];

const MONTHS = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
];

const TYPE_BADGE_MAP = {
    'New Application': 'badge--application',
    'Fund Switch In':  'badge--switch-in',
    'Fund Redemption': 'badge--redemption',
    'Fund Switch Out': 'badge--switch-out'
};

export default class FundTransactionList extends LightningElement {
    @track _rawRecords  = [];
    @track totalCount   = 0;
    @track currentPage  = 1;
    @track isLoading    = true;
    @track hasError     = false;
    @track errorMessage = '';
    @track showModal    = false;
    @track editRecordId = null;
    @track expandedIds  = new Set();
    @track fundOptions  = [{ label: 'All Funds', value: '' }];

    // Multi-select filter state
    @track _selectedFundIds = [];
    @track _selectedTxTypes = [];
    @track _selectedMonths  = [];
    @track _intrafundOnly   = false;

    // Combobox "add" values (reset after each selection)
    @track _addFundValue  = '';
    @track _addTypeValue  = '';
    @track _addMonthValue = '';

    wiredTransactionsResult;

    // --- Wires ---
    @wire(getFunds)
    wiredFunds({ data }) {
        if (data) {
            this.fundOptions = [
                { label: 'All Funds', value: '' },
                ...data.map(f => ({ label: f.Name, value: f.Id }))
            ];
        }
    }

    @wire(getTransactions, {
        fundIds:      '$_selectedFundIds',
        txTypes:      '$_selectedTxTypes',
        months:       '$_selectedMonths',
        intrafundOnly: '$_intrafundOnly',
        pageSize:     PAGE_SIZE,
        offset:       '$offset'
    })
    wiredTransactions(result) {
        this.wiredTransactionsResult = result;
        this.isLoading = false;
        if (result.data) {
            this.totalCount  = result.data.total;
            this._rawRecords = result.data.records;
            this.hasError    = false;
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error.body?.message || 'Failed to load transactions.';
        }
    }

    // --- Computed ---
    get offset()      { return (this.currentPage - 1) * PAGE_SIZE; }
    get totalPages()  { return Math.max(1, Math.ceil(this.totalCount / PAGE_SIZE)); }
    get isFirstPage() { return this.currentPage === 1; }
    get isLastPage()  { return this.currentPage >= this.totalPages; }
    get hasRecords()  { return this._rawRecords.length > 0; }

    get showIntrafundFilter() { return hasFullAccess; }

    get paginationLabel() {
        const start = this.offset + 1;
        const end   = Math.min(this.offset + PAGE_SIZE, this.totalCount);
        return `Showing ${start}–${end} of ${this.totalCount}`;
    }

    get formattedTotalAmount() {
        const sum = this.records.reduce((acc, r) => acc + (r.Amount__c || 0), 0);
        return new Intl.NumberFormat('en-AU', {
            style: 'currency', currency: 'AUD', maximumFractionDigits: 0
        }).format(sum);
    }

    get applicationCount() {
        return this.records.filter(r => r.Transaction_Type__c === 'New Application').length;
    }

    get redemptionCount() {
        return this.records.filter(r => r.Transaction_Type__c === 'Fund Redemption').length;
    }

    // --- Filter options (excludes already-selected) ---
    get availableFundOptions() {
        return this.fundOptions.filter(o => o.value && !this._selectedFundIds.includes(o.value));
    }

    get availableTypeOptions() {
        return TX_TYPE_OPTIONS.filter(o => o.value && !this._selectedTxTypes.includes(o.value));
    }

    get availableMonthOptions() {
        return MONTHS
            .filter(m => !this._selectedMonths.includes(m))
            .map(m => ({ label: m, value: m }));
    }

    // --- Selected pill getters ---
    get selectedFundPills() {
        return this._selectedFundIds.map(id => {
            const opt = this.fundOptions.find(o => o.value === id);
            return { value: id, label: opt ? opt.label : id };
        });
    }

    get selectedTypePills() {
        return this._selectedTxTypes.map(v => ({ value: v, label: v }));
    }

    get selectedMonthPills() {
        return this._selectedMonths.map(m => ({ value: m, label: m }));
    }

    // --- Row decoration ---
    get records() {
        return this._rawRecords.map(r => {
            const isExpanded = this.expandedIds.has(r.Id);
            return {
                ...r,
                isExpanded,
                expandKey:          r.Id + '_expand',
                expandIcon:         isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass:           'tx-row' + (r.Restricted_Entity__c ? ' tx-row--restricted' : ''),
                typeBadgeClass:     'type-badge ' + (TYPE_BADGE_MAP[r.Transaction_Type__c] || ''),
                formattedAmount:    this.formatCurrency(r.Amount__c),
                amountDirection:    ['Fund Redemption','Fund Switch Out'].includes(r.Transaction_Type__c) ? 'out' : 'in',
                intrafundLabel:     r.Intrafund__c ? 'Yes' : 'No',
                moneyReceivedLabel: r.Money_Received__c ? 'Yes' : 'No',
                fundName:           r.Fund__r          ? r.Fund__r.Name          : '—',
                vehicleName:        r.Investment_Vehicle_Type__c === 'Financial Instrument'
                    ? (r.Financial_Instrument__r ? r.Financial_Instrument__r.Name : '—')
                    : r.Investment_Vehicle_Type__c === 'Warehouse Note'
                    ? (r.Warehouse_Note__r ? r.Warehouse_Note__r.Name : '—')
                    : (r.Fund__r ? r.Fund__r.Name : '—'),
                bdmName:            r.BDM__r           ? r.BDM__r.Name           : '—',
                switchedFromName:   r.Switched_From__r ? r.Switched_From__r.Name : '—',
                displayDate:        this.formatDate(r.Transaction_Date__c),
                displaySwitchDate:  this.formatDate(r.Switch_Completed__c),
                displayMoneyDate:   this.formatDate(r.Money_Received_On__c)
            };
        });
    }

    formatCurrency(val) {
        if (val == null) return '—';
        return new Intl.NumberFormat('en-AU', {
            style: 'currency', currency: 'AUD', maximumFractionDigits: 0
        }).format(val);
    }

    formatDate(dateStr) {
        if (!dateStr) return '—';
        const parts = String(dateStr).split('-');
        if (parts.length !== 3) return dateStr;
        return `${parts[2]}-${parts[1]}-${parts[0]}`;
    }

    // --- Filter handlers (multi-select add) ---
    handleAddFund(event) {
        const val = event.detail.value;
        if (!val || this._selectedFundIds.includes(val)) { this._addFundValue = ''; return; }
        this.isLoading        = true;
        this._selectedFundIds = [...this._selectedFundIds, val];
        this._addFundValue    = '';
        this.currentPage      = 1;
    }

    handleAddType(event) {
        const val = event.detail.value;
        if (!val || this._selectedTxTypes.includes(val)) { this._addTypeValue = ''; return; }
        this.isLoading        = true;
        this._selectedTxTypes = [...this._selectedTxTypes, val];
        this._addTypeValue    = '';
        this.currentPage      = 1;
    }

    handleAddMonth(event) {
        const val = event.detail.value;
        if (!val || this._selectedMonths.includes(val)) { this._addMonthValue = ''; return; }
        this.isLoading       = true;
        this._selectedMonths = [...this._selectedMonths, val];
        this._addMonthValue  = '';
        this.currentPage     = 1;
    }

    handleIntrafundFilter(e) {
        this.isLoading      = true;
        this._intrafundOnly = e.detail.checked;
        this.currentPage    = 1;
    }

    // --- Filter handlers (pill remove) ---
    handleRemoveFundFilter(event) {
        const val = event.currentTarget.dataset.value;
        this.isLoading        = true;
        this._selectedFundIds = this._selectedFundIds.filter(id => id !== val);
        this.currentPage      = 1;
    }

    handleRemoveTypeFilter(event) {
        const val = event.currentTarget.dataset.value;
        this.isLoading        = true;
        this._selectedTxTypes = this._selectedTxTypes.filter(v => v !== val);
        this.currentPage      = 1;
    }

    handleRemoveMonthFilter(event) {
        const val = event.currentTarget.dataset.value;
        this.isLoading       = true;
        this._selectedMonths = this._selectedMonths.filter(m => m !== val);
        this.currentPage     = 1;
    }

    clearFilters() {
        this.isLoading        = true;
        this._selectedFundIds = [];
        this._selectedTxTypes = [];
        this._selectedMonths  = [];
        this._intrafundOnly   = false;
        this._addFundValue    = '';
        this._addTypeValue    = '';
        this._addMonthValue   = '';
        this.currentPage      = 1;
    }

    // --- Pagination ---
    handlePrevPage() { if (!this.isFirstPage) this.currentPage--; }
    handleNextPage() { if (!this.isLastPage)  this.currentPage++; }

    // --- Row expand ---
    handleExpandRow(event) {
        event.stopPropagation();
        const id   = event.currentTarget.dataset.id;
        const next = new Set(this.expandedIds);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        this.expandedIds = next;
    }

    // --- Modal ---
    handleNewTransaction() {
        this.editRecordId = null;
        this.showModal    = true;
    }

    handleEditRow(event) {
        event.stopPropagation();
        this.editRecordId = event.currentTarget.dataset.id;
        this.showModal    = true;
    }

    handleModalClose() {
        this.showModal    = false;
        this.editRecordId = null;
    }

    handleModalSave() {
        this.showModal = false;
        refreshApex(this.wiredTransactionsResult);
    }
}
