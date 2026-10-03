import { LightningElement, track, wire } from 'lwc';
import getFundFlowSummary       from '@salesforce/apex/FundTransactionAnalyticsController.getFundFlowSummary';
import getBDMPerformance        from '@salesforce/apex/FundTransactionAnalyticsController.getBDMPerformance';
import getTransactionBreakdown  from '@salesforce/apex/FundTransactionAnalyticsController.getTransactionBreakdown';
import getSwitchFlowMap         from '@salesforce/apex/FundTransactionAnalyticsController.getSwitchFlowMap';
import getAvailableMonths       from '@salesforce/apex/FundTransactionAnalyticsController.getAvailableMonths';
import getFunds                 from '@salesforce/apex/FundTransactionController.getFunds';

const TYPE_BADGE_MAP = {
    'New Application': 'type-badge badge--application',
    'Fund Switch In':  'type-badge badge--switch-in',
    'Fund Redemption': 'type-badge badge--redemption',
    'Fund Switch Out': 'type-badge badge--switch-out'
};

const formatAUD = (val) =>
    new Intl.NumberFormat('en-AU', { style: 'currency', currency: 'AUD', maximumFractionDigits: 0 }).format(val || 0);

export default class FundTransactionAnalytics extends LightningElement {
    @track activeTab      = 'fundFlow';
    @track selectedMonth  = '';
    @track selectedFund   = '';
    @track isLoading      = false;
    @track analyticsError = null;

    @track fundFlowData  = [];
    @track bdmData       = [];
    @track breakdownData = [];
    @track switchData    = [];
    @track monthOptions  = [{ label: 'All Months', value: '' }];
    @track fundOptions   = [{ label: 'All Funds', value: '' }];

    @wire(getAvailableMonths)
    wiredMonths({ data }) {
        if (data) {
            const MONTHS = ['January','February','March','April','May','June',
                            'July','August','September','October','November','December'];
            this.monthOptions = [
                { label: 'All Months', value: '' },
                ...data.map(m => {
                    const [yr, mo] = m.split('-').map(Number);
                    return { label: MONTHS[mo - 1] + ' ' + yr, value: m };
                })
            ];
        }
    }

    @wire(getFunds)
    wiredFunds({ data }) {
        if (data) {
            this.fundOptions = [
                { label: 'All Funds', value: '' },
                ...data.map(f => ({ label: f.Name, value: f.Id }))
            ];
        }
    }

    connectedCallback() {
        this.loadAll();
    }

    loadAll() {
        this.isLoading      = true;
        this.analyticsError = null;
        const month = this.selectedMonth;
        const fund  = this.selectedFund;

        Promise.all([
            getFundFlowSummary({ month, fundId: fund }),
            getBDMPerformance({ month, fundId: fund }),
            getTransactionBreakdown({ fundId: fund, month }),
            getSwitchFlowMap({ month, fundId: fund })
        ])
        .then(([ff, bdm, bd, sw]) => {
            this.fundFlowData  = ff  || [];
            this.bdmData       = bdm || [];
            this.breakdownData = bd  || [];
            this.switchData    = sw  || [];
            this.isLoading     = false;
        })
        .catch((err) => {
            this.analyticsError = (err?.body?.message) || (err?.message) || JSON.stringify(err);
            this.isLoading      = false;
            console.error('Analytics load error', err);
        });
    }

    // --- Tab ---
    get isFundFlowTab()  { return this.activeTab === 'fundFlow'; }
    get isBDMTab()       { return this.activeTab === 'bdm'; }
    get isBreakdownTab() { return this.activeTab === 'breakdown'; }
    get isSwitchMapTab() { return this.activeTab === 'switchMap'; }

    tabClass(tab) { return 'a-tab-btn' + (this.activeTab === tab ? ' a-tab-btn--active' : ''); }
    get fundFlowTabClass()  { return this.tabClass('fundFlow'); }
    get bdmTabClass()       { return this.tabClass('bdm'); }
    get breakdownTabClass() { return this.tabClass('breakdown'); }
    get switchMapTabClass() { return this.tabClass('switchMap'); }

    handleAnalyticsTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.loadAll();
    }

    handleFundChange(event) {
        this.selectedFund = event.detail.value;
        this.loadAll();
    }

    refreshAll() { this.loadAll(); }

    // --- Data rows ---
    get hasFundFlowData()  { return this.fundFlowRows.length > 0; }
    get hasBDMData()       { return this.bdmRows.length > 0; }
    get hasBreakdownData() { return this.breakdownRows.length > 0; }
    get hasSwitchData()    { return this.switchRows.length > 0; }

    get fundFlowRows() {
        return this.fundFlowData.map((r, i) => ({
            key:            i,
            fundName:       r.fundName,
            txType:         r.txType,
            txCount:        r.txCount,
            formattedTotal: formatAUD(r.total),
            typeBadgeClass: TYPE_BADGE_MAP[r.txType] || 'type-badge',
            subtotalClass:  'analytics-row'
        }));
    }

    get bdmRows() {
        return this.bdmData.map((r, i) => ({
            key:            i,
            bdmName:        r.bdmName || '(Unassigned)',
            txType:         r.txType,
            txCount:        r.txCount,
            formattedTotal: formatAUD(r.total),
            typeBadgeClass: TYPE_BADGE_MAP[r.txType] || 'type-badge'
        }));
    }

    get breakdownRows() {
        const MONTHS = ['January','February','March','April','May','June',
                        'July','August','September','October','November','December'];
        return this.breakdownData.map((r, i) => ({
            key:            i,
            month:          r.mo ? (MONTHS[r.mo - 1] + ' ' + r.yr) : '—',
            txType:         r.txType,
            txCount:        r.txCount,
            formattedTotal: formatAUD(r.total),
            typeBadgeClass: TYPE_BADGE_MAP[r.txType] || 'type-badge'
        }));
    }

    get switchRows() {
        return this.switchData.map((r, i) => ({
            key:            i,
            fundName:       r.fundName,
            switchedFrom:   r.switchedFrom || '—',
            txType:         r.txType,
            txCount:        r.txCount,
            formattedTotal: formatAUD(r.total),
            typeBadgeClass: TYPE_BADGE_MAP[r.txType] || 'type-badge'
        }));
    }
}
