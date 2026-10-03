import { LightningElement, api, wire } from 'lwc';
import getKpis from '@salesforce/apex/DebtPositionKpiController.getKpis';

export default class DebtPositionKpiStrip extends LightningElement {
    @api recordId;
    tiles = [];

    @wire(getKpis, { recordId: '$recordId' })
    wired({ data }) {
        if (!data) return;

        // Payment health: amber if overdue or due today, green otherwise
        const paymentClass = data.daysToPayment === 0
            ? 'kpi-tile health-alert'
            : data.daysToPayment <= 7
                ? 'kpi-tile health-warn'
                : 'kpi-tile health-good';

        // Maturity health: amber if < 90 days remaining
        const maturityClass = data.daysToMaturity > 0 && data.daysToMaturity < 90
            ? 'kpi-tile health-alert'
            : 'kpi-tile';

        this.tiles = [
            {
                key: 'outstanding',
                label: 'Outstanding Balance',
                value: data.outstandingFormatted,
                subtext: data.outstandingDelta,
                tileClass: 'kpi-tile'
            },
            {
                key: 'nextPayment',
                label: 'Next Payment Due',
                value: data.nextPaymentFormatted,
                subtext: data.nextPaymentDate + (data.daysToPayment > 0 ? ' · ' + data.daysToPayment + ' days' : ''),
                tileClass: paymentClass
            },
            {
                key: 'accrued',
                label: 'Accrued Interest YTD',
                value: data.accruedYtdFormatted,
                subtext: 'As of ' + data.asOf,
                tileClass: 'kpi-tile'
            },
            {
                key: 'maturity',
                label: 'Days to Maturity',
                value: data.daysToMaturity,
                subtext: data.maturityYearsRemaining,
                tileClass: maturityClass
            },
            {
                key: 'drawn',
                label: 'Drawn / Undrawn',
                value: data.drawnUndrawn,
                subtext: data.utilisedPct > 0 ? data.utilisedPct + '% utilised' : 'No facility limit on record',
                tileClass: data.utilisedPct > 90 ? 'kpi-tile health-alert' : 'kpi-tile'
            },
            {
                key: 'rate',
                label: 'Current Rate',
                value: data.currentRateFormatted,
                subtext: data.rateBreakdown,
                tileClass: 'kpi-tile'
            }
        ];
    }
}
