import { LightningElement, wire, track } from 'lwc';
import getExceptions from '@salesforce/apex/ExceptionsInboxController.getExceptions';

export default class ExceptionsInbox extends LightningElement {
    @track items = [];

    @wire(getExceptions)
    wired({ data }) {
        if (data) {
            this.items = data;
        }
    }

    get hasItems()      { return this.items.length > 0; }
    get itemCountLabel(){ return `${this.items.length} item${this.items.length !== 1 ? 's' : ''}`; }

    get displayItems() {
        return this.items.map(item => ({
            ...item,
            iconClass: 'exception-icon ' + (
                item.severity === 'error'   ? 'icon-error'   :
                item.severity === 'warning' ? 'icon-warning' : 'icon-info'
            )
        }));
    }

    handleAction(event) {
        const id   = event.currentTarget.dataset.id;
        const type = event.currentTarget.dataset.type;
        if (id && type) {
            // eslint-disable-next-line no-restricted-globals
            window.location.href = `/lightning/r/${type}/${id}/view`;
        }
    }
}
