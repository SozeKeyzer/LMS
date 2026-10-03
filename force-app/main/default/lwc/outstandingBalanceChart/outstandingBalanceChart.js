import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getCashflows from '@salesforce/apex/CashflowChartController.getCashflows';

const SVG_W      = 780;
const SVG_H      = 240;
const PAD_LEFT   = 80;
const PAD_RIGHT  = 16;
const PAD_TOP    = 16;
const PAD_BOTTOM = 50;
const CHART_W    = SVG_W - PAD_LEFT - PAD_RIGHT;
const CHART_H    = SVG_H - PAD_TOP - PAD_BOTTOM;
const Y_STEPS    = 4;

function fmt(v) {
    return '$' + Number(v).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

export default class OutstandingBalanceChart extends LightningElement {
    @api recordId;

    @track _error;
    cashflowData;
    _wiredResult;

    @wire(getCashflows, { recordId: '$recordId', mode: 'tranche' })
    wired(result) {
        this._wiredResult = result;
        if (result.data)  { this.cashflowData = result.data; this._error = null; }
        else if (result.error) {
            this._error = result.error.body?.message || result.error.message || 'Load error';
            this.cashflowData = null;
        }
    }

    @api refresh() {
        if (this._wiredResult) refreshApex(this._wiredResult);
    }

    get chartSvg() {
        const data = this.cashflowData;
        if (!data || data.length === 0) return null;

        // Outstanding balance = starting total principal, reduced by each principal payment.
        // For a bullet loan: balance stays flat until maturity. For amortising: steps down.
        const totalPrincipal = data.reduce((s, c) => s + (c.principal || 0), 0);
        if (totalPrincipal === 0) return null;  // no principal data yet

        const balances = [];
        let remaining = totalPrincipal;
        for (const c of data) {
            balances.push({ period: c.period, balance: remaining });
            remaining -= (c.principal || 0);
        }
        // Add post-maturity zero point
        balances.push({ period: data[data.length - 1].period, balance: Math.max(0, remaining) });

        const maxVal = totalPrincipal;

        // Y-axis
        const yAxis = [];
        for (let i = 0; i <= Y_STEPS; i++) {
            const val = (maxVal * i) / Y_STEPS;
            const cy  = PAD_TOP + CHART_H - (CHART_H * i) / Y_STEPS;
            yAxis.push({ lineKey: `yl${i}`, textKey: `yt${i}`, cy, label: fmt(val), lineY: cy });
        }

        // Polyline points
        const n = balances.length;
        const pts = balances.map((b, i) => {
            const x = PAD_LEFT + (i / (n - 1)) * CHART_W;
            const y = PAD_TOP + CHART_H - (b.balance / maxVal) * CHART_H;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');

        // Dots with tooltips
        const dots = balances.slice(0, -1).map((b, i) => {
            const x = PAD_LEFT + (i / (n - 1)) * CHART_W;
            const y = PAD_TOP + CHART_H - (b.balance / maxVal) * CHART_H;
            return {
                key:    `d${i}`,
                cx:     x.toFixed(1),
                cy:     y.toFixed(1),
                period: b.period,
                label:  fmt(b.balance)
            };
        });

        // X-axis date labels (show every nth to avoid crowding)
        const step = Math.ceil(balances.length / 8);
        const xLabels = balances.slice(0, -1)
            .filter((_, i) => i % step === 0 || i === balances.length - 2)
            .map((b, _, arr) => {
                const i = balances.indexOf(b);
                const x = PAD_LEFT + (i / (n - 1)) * CHART_W;
                return { key: `xl${i}`, x: x.toFixed(1), y: PAD_TOP + CHART_H + 18, label: b.period.slice(2) };
            });

        return {
            viewBox:      `0 0 ${SVG_W} ${SVG_H}`,
            chartBottom:  PAD_TOP + CHART_H,
            chartRight:   PAD_LEFT + CHART_W,
            yAxis, pts, dots, xLabels
        };
    }

    get hasError()  { return !!this._error; }
    get errorMsg()  { return this._error; }
    get hasData()   { return !this._error && !!this.chartSvg; }
    get isEmpty()   { return !this._error && this.cashflowData && !this.chartSvg; }
    get isLoading() { return !this._error && !this.cashflowData; }
}
