import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJs from '@salesforce/resourceUrl/chartjs';
import getCashflows from '@salesforce/apex/CashflowChartController.getCashflows';

export default class MaturityLadderChart extends LightningElement {
    @api dealId;
    @api mode = 'aggregate';

    @track _errorMessage;
    @track _hasData = false;

    chart;
    chartJsInitialized = false;
    _loadingScript = false;
    _loadFailed    = false;
    chartData;

    @wire(getCashflows, { recordId: '$dealId', mode: '$mode' })
    wired(result) {
        if (result.data) {
            this.chartData     = result.data;
            this._errorMessage = null;
            this._hasData      = result.data.some(c => c.principal > 0);
            this.renderChart();
        } else if (result.error) {
            this._errorMessage = result.error.body?.message
                || result.error.message
                || 'Failed to load maturity data.';
            this.chartData = null;
            this._hasData  = false;
            this._destroyChart();
        }
    }

    async renderedCallback() {
        if (this.chartJsInitialized || this._loadingScript || this._loadFailed) return;
        this._loadingScript = true;
        try {
            await loadScript(this, ChartJs);
            this.chartJsInitialized = true;
            this.renderChart();
        } catch (err) {
            this._loadFailed   = true;
            this._errorMessage = 'Chart library failed to load: '
                + (err?.message || err?.body?.message || String(err));
        } finally {
            this._loadingScript = false;
        }
    }

    disconnectedCallback() {
        this._destroyChart();
    }

    // Chart.js 2.9.4 API
    renderChart() {
        if (!this.chartJsInitialized || !this.chartData) return;
        const principalData = this.chartData.map(c => c.principal || 0);
        if (!principalData.some(v => v > 0)) return;
        const ctx = this.template.querySelector('canvas');
        if (!ctx) return;
        this._destroyChart();

        // eslint-disable-next-line no-undef
        this.chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels:   this.chartData.map(c => c.period),
                datasets: [{
                    label:           'Principal Maturities',
                    data:            principalData,
                    backgroundColor: '#0176d3',
                    stack:           'maturities'
                }]
            },
            options: {
                responsive:          true,
                maintainAspectRatio: false,
                scales: {
                    xAxes: [{ stacked: true }],
                    yAxes: [{
                        stacked: true,
                        ticks: {
                            beginAtZero: true,
                            callback: (v) => {
                                if (v >= 1000000) return '$' + (v / 1000000).toFixed(1) + 'M';
                                if (v >= 1000)    return '$' + (v / 1000).toFixed(0) + 'K';
                                return '$' + v;
                            }
                        }
                    }]
                },
                tooltips: {
                    callbacks: {
                        label: (item) => '$' + Number(item.yLabel).toLocaleString('en-US', {
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 2
                        })
                    }
                }
            }
        });
    }

    _destroyChart() {
        if (this.chart) {
            this.chart.destroy();
            this.chart = null;
        }
    }

    get hasError()    { return !!this._errorMessage; }
    get errorMsg()    { return this._errorMessage; }
    get showEmpty()   { return !this._errorMessage && this.chartData && !this._hasData; }
    get isLoading()   { return !this._errorMessage && !this.chartData && this.dealId; }
    get canvasClass() { return this._hasData && !this._errorMessage ? '' : 'canvas-hidden'; }
}
