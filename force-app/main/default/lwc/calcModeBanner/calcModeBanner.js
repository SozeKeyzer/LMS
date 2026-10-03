import { LightningElement, api } from 'lwc';

export default class CalcModeBanner extends LightningElement {
    @api recordId;
    @api calcMode = 'Engine';
    @api modeSince = '';
    @api reason = '';
    @api owner = '';
    @api episodeName = '';

    get isManual() { return this.calcMode === 'Manual'; }
    get isHybrid() { return this.calcMode === 'Hybrid'; }
    get isEngine() { return this.calcMode === 'Engine'; }
    get episodeLabel() {
        return this.episodeName ? 'View Episode ' + this.episodeName : 'View Episode';
    }

    viewEpisode()    { this.dispatchEvent(new CustomEvent('viewepisode')); }
    returnToEngine() { this.dispatchEvent(new CustomEvent('returntoeengine')); }
    switchToManual() { this.dispatchEvent(new CustomEvent('switchtomanual')); }
}
