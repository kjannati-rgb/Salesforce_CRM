import { LightningElement, api, wire } from 'lwc';
import getObjectives from '@salesforce/apex/AccountPlanController.getObjectives';

const STATUS_CLASS = {
    Not_Started: 'badge st-ns',
    In_Progress: 'badge st-ip',
    At_Risk: 'badge st-risk',
    Done: 'badge st-done'
};
const STATUS_LABEL = {
    Not_Started: 'Not Started',
    In_Progress: 'In Progress',
    At_Risk: 'At Risk',
    Done: 'Done'
};

export default class ObjectivesPanel extends LightningElement {
    @api recordId;
    objectives = [];
    error;

    @wire(getObjectives, { planId: '$recordId' })
    wiredObjectives({ data, error }) {
        if (data) {
            this.objectives = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.objectives = [];
        }
    }

    get hasData() {
        return this.objectives && this.objectives.length > 0;
    }

    get items() {
        return this.objectives.map((o) => {
            const pct = o.progress != null ? Math.max(0, Math.min(100, Math.round(o.progress))) : 0;
            return {
                id: o.id,
                title: o.title,
                owner: o.owner,
                linkedFamily: o.linkedFamily,
                statusClass: STATUS_CLASS[o.status] || 'badge st-ns',
                statusLabel: STATUS_LABEL[o.status] || o.status,
                pctLabel: pct + '%',
                barStyle: 'width:' + pct + '%'
            };
        });
    }
}
