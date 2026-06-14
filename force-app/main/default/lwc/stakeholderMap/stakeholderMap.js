import { LightningElement, api, wire } from 'lwc';
import getStakeholders from '@salesforce/apex/AccountPlanController.getStakeholders';

const INFLUENCE = ['High', 'Medium', 'Low'];
const SENTIMENT = ['Champion', 'Supporter', 'Neutral', 'Detractor'];
const SENT_CLASS = {
    Champion: 'champion',
    Supporter: 'supporter',
    Neutral: 'neutral',
    Detractor: 'detractor'
};

export default class StakeholderMap extends LightningElement {
    @api recordId;
    stakeholders = [];
    error;

    @wire(getStakeholders, { planId: '$recordId' })
    wiredStakeholders({ data, error }) {
        if (data) {
            this.stakeholders = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.stakeholders = [];
        }
    }

    get hasData() {
        return this.stakeholders && this.stakeholders.length > 0;
    }

    get columns() {
        return SENTIMENT;
    }

    get rows() {
        return INFLUENCE.map((inf) => {
            const cells = SENTIMENT.map((sent) => {
                const people = this.stakeholders.filter(
                    (s) => s.influence === inf && s.sentiment === sent
                );
                return {
                    key: inf + '-' + sent,
                    cssClass: 'hcell ' + (people.length ? SENT_CLASS[sent] : 'empty'),
                    people: people.map((p) => ({
                        id: p.id,
                        label: p.name + (p.role ? ' · ' + p.role : '')
                    }))
                };
            });
            return { key: inf, label: inf, cells };
        });
    }

    get coverage() {
        const champ = this.stakeholders.filter((s) => s.sentiment === 'Champion').length;
        const detr = this.stakeholders.filter((s) => s.sentiment === 'Detractor').length;
        return (
            this.stakeholders.length +
            ' mapped · ' +
            champ +
            ' champion' +
            (champ === 1 ? '' : 's') +
            ' · ' +
            detr +
            ' detractor' +
            (detr === 1 ? '' : 's')
        );
    }
}
