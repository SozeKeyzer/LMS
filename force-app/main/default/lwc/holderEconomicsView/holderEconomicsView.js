import { LightningElement, api, wire, track } from 'lwc';
import getHolders from '@salesforce/apex/HolderEconomicsController.getHolders';

export default class HolderEconomicsView extends LightningElement {
    @api recordId;
    @api mode = 'tranche';
    @track holderRows = [];
    @track errorMessage;

    columns = [
        { label: 'Holder', fieldName: 'holderName' },
        { label: 'Commitment', fieldName: 'commitment', type: 'currency' },
        { label: '% Share', fieldName: 'pctShare', type: 'percent',
          typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 2 } }
    ];

    @wire(getHolders, { recordId: '$recordId', mode: '$mode' })
    wired({ data, error }) {
        if (data) {
            this.holderRows = data;
            this.errorMessage = null;
        } else if (error) {
            this.errorMessage = error.body?.message || error.message || JSON.stringify(error);
            this.holderRows = [];
        }
    }

    get hasError()    { return !!this.errorMessage; }
    get isEmpty()     { return !this.errorMessage && this.holderRows.length === 0; }
    get hasData()     { return this.holderRows.length > 0; }
}
