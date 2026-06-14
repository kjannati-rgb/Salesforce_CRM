import { LightningElement, api, wire } from 'lwc';
import getSignals from '@salesforce/apex/AccountPlanController.getSignals';

const SEV_CLASS = { High: 'dot r', Medium: 'dot o', Low: 'dot g' };

export default class KeySignals extends LightningElement {
    @api recordId;
    signals = [];
    error;

    @wire(getSignals, { planId: '$recordId' })
    wiredSignals({ data, error }) {
        if (data) {
            this.signals = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.signals = [];
        }
    }

    get hasData() {
        return this.signals && this.signals.length > 0;
    }

    get items() {
        return this.signals.map((s) => {
            const meta = [s.source, s.severity, s.signalType].filter((p) => p).join(' · ');
            return {
                id: s.id,
                dotClass: SEV_CLASS[s.severity] || 'dot o',
                summary: s.summary,
                recommendedAction: s.recommendedAction,
                meta
            };
        });
    }
}
