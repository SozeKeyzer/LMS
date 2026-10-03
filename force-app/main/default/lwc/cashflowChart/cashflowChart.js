import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getCashflows from '@salesforce/apex/CashflowChartController.getCashflows';

const COLOURS = {
    principal: '#0176d3',
    interest:  '#1b96ff',
    fees:      '#fe9339',
    pik:       '#730394'
};

const SVG_W        = 780;
const SVG_H        = 320;
const PAD_LEFT     = 72;
const PAD_RIGHT    = 16;
const PAD_TOP      = 16;
const PAD_BOTTOM   = 54;
const CHART_W      = SVG_W - PAD_LEFT - PAD_RIGHT;
const CHART_H      = SVG_H - PAD_TOP - PAD_BOTTOM;
const Y_STEPS      = 5;

function fmt(v) {
    return '$' + Number(v).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

export default class CashflowChart extends LightningElement {
    @api recordId;
    @api dealId;
    @api mode = 'tranche';

    @track _error;
    cashflowData;
    _wiredResult;

    @wire(getCashflows, { recordId: '$recordId', mode: '$mode' })
    wired(result) {
        this._wiredResult = result;
        if (result.data) {
            this.cashflowData = result.data;
            this._error = null;
        } else if (result.error) {
            this._error = result.error.body?.message || result.error.message || 'Load error';
            this.cashflowData = null;
        }
    }

    @api refresh() {
        if (this._wiredResult) refreshApex(this._wiredResult);
    }

    // ── SVG chart computation ─────────────────────────────────────────────────
    get chartSvg() {
        const data = this.cashflowData;
        if (!data || data.length === 0) return null;

        // Totals per period
        const totals = data.map(c =>
            (c.principal || 0) + (c.interest || 0) + (c.fees || 0) + (c.pik || 0));
        const maxVal = Math.max(...totals, 1);

        // Bar sizing
        const barSlot = CHART_W / data.length;
        const barW    = Math.max(4, Math.floor(barSlot * 0.65));
        const barX0   = PAD_LEFT + (barSlot - barW) / 2;

        // Y-axis grid lines and labels — separate keys for line and text siblings
        const yAxis = [];
        for (let i = 0; i <= Y_STEPS; i++) {
            const val = (maxVal * i) / Y_STEPS;
            const cy  = PAD_TOP + CHART_H - (CHART_H * i) / Y_STEPS;
            yAxis.push({ lineKey: `yl${i}`, textKey: `yt${i}`, cy, label: fmt(val), lineY: cy });
        }

        // Bars
        const bars = data.map((c, idx) => {
            const x   = Math.round(barX0 + idx * barSlot);
            const lx  = Math.round(x + barW / 2);
            let   baseY = PAD_TOP + CHART_H;
            const segs  = [];

            for (const key of ['principal', 'interest', 'fees', 'pik']) {
                const val = c[key] || 0;
                if (val <= 0) continue;
                const h = Math.max(1, (val / maxVal) * CHART_H);
                baseY -= h;
                segs.push({
                    key: `${idx}-${key}`,
                    x, y: Math.round(baseY), w: barW, h: Math.ceil(h),
                    fill: COLOURS[key],
                    label: key.charAt(0).toUpperCase() + key.slice(1),
                    value: fmt(val)
                });
            }

            // X label: show month-day only if many bars, else full date
            const label = data.length > 8
                ? c.period.slice(5)   // MM-DD
                : c.period.slice(2);  // YY-MM-DD

            return {
                totalKey:  `bt${idx}`,
                xLabelKey: `bx${idx}`,
                segs,
                lx, ly: PAD_TOP + CHART_H + 16,
                label,
                total: fmt(totals[idx]),
                totalY: Math.round(PAD_TOP + CHART_H - (totals[idx] / maxVal) * CHART_H - 4)
            };
        });

        // Which datasets have any non-zero value (for legend)
        const activeKeys = ['principal', 'interest', 'fees', 'pik'].filter(k =>
            data.some(c => (c[k] || 0) > 0));

        const legendItems = activeKeys.map((k, i) => ({
            rectKey:  `lr${k}`,
            textKey:  `lt${k}`,
            fill: COLOURS[k],
            label: k.charAt(0).toUpperCase() + k.slice(1),
            lx: PAD_LEFT + i * 120
        }));

        return {
            viewBox: `0 0 ${SVG_W} ${SVG_H}`,
            chartBottom: PAD_TOP + CHART_H,
            chartRight: PAD_LEFT + CHART_W,
            yAxis, bars, legendItems,
            legendY: SVG_H - 10
        };
    }

    get hasError()  { return !!this._error; }
    get errorMsg()  { return this._error; }
    get hasData()   { return !this._error && this.cashflowData && this.cashflowData.length > 0; }
    get isEmpty()   { return !this._error && this.cashflowData && this.cashflowData.length === 0; }
    get isLoading() { return !this._error && !this.cashflowData; }
}
