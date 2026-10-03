import { LightningElement, track } from 'lwc';
import hasImportPerm from '@salesforce/customPermission/Fund_Transaction_Importer';

export default class FundTransactionApp extends LightningElement {
    @track activeTab = 'list';

    get showImportTab() {
        return hasImportPerm;
    }

    get isListTab()      { return this.activeTab === 'list'; }
    get isBulkTab()      { return this.activeTab === 'bulk'; }
    get isImportTab()    { return this.activeTab === 'import'; }
    get isAnalyticsTab() { return this.activeTab === 'analytics'; }

    get listTabClass()      { return this.tabClass('list'); }
    get bulkTabClass()      { return this.tabClass('bulk'); }
    get importTabClass()    { return this.tabClass('import'); }
    get analyticsTabClass() { return this.tabClass('analytics'); }

    tabClass(tab) {
        return 'tab-btn' + (this.activeTab === tab ? ' tab-btn--active' : '');
    }

    handleTabSelect(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleRefresh() {
        this.activeTab = 'list';
    }
}
