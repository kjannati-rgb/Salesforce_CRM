import { LightningElement, api, wire } from 'lwc';
import getTeam from '@salesforce/apex/AccountPlanController.getTeam';

const ROLE_LABEL = {
    Plan_Lead: 'Plan Lead',
    Lane_Owner: 'Lane Owner',
    SDR: 'SDR',
    Contributor: 'Contributor'
};
const ROLE_CLASS = {
    Plan_Lead: 'badge lead',
    Lane_Owner: 'badge lane',
    SDR: 'badge sdr',
    Contributor: 'badge contrib'
};

export default class PlanTeam extends LightningElement {
    @api recordId;
    team = [];
    error;

    @wire(getTeam, { planId: '$recordId' })
    wiredTeam({ data, error }) {
        if (data) {
            this.team = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.team = [];
        }
    }

    get hasData() {
        return this.team && this.team.length > 0;
    }

    get members() {
        return this.team.map((t) => ({
            id: t.id,
            name: t.name,
            lane: t.lane,
            roleLabel: ROLE_LABEL[t.role] || t.role,
            roleClass: ROLE_CLASS[t.role] || 'badge contrib'
        }));
    }
}
