import { LightningElement, track } from 'lwc';

export default class ManualEntrySignalTile extends LightningElement {
    @track currentPeriodCount = 0;
    @track ytdCount = 0;
    @track byObject = [];

    get isHighSignal() { return this.currentPeriodCount > 10; }

    connectedCallback() {
        // Wire to getManualEntrySignal Apex in full impl
    }
}