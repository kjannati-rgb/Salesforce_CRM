import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
    wiredResult;
    showForm = false;
    editId;
    saving = false;

    @wire(getTeam, { planId: '$recordId' })
    wiredTeam(result) {
        this.wiredResult = result;
        const { data, error } = result;
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

    get formTitle() {
        return this.editId ? 'Edit team member' : 'New team member';
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

    handleNew() {
        this.editId = undefined;
        this.showForm = true;
    }

    handleEdit(event) {
        this.editId = event.currentTarget.dataset.id;
        this.showForm = true;
    }

    handleCancel() {
        this.showForm = false;
        this.editId = undefined;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };
        if (!this.editId) {
            fields.Account_Plan__c = this.recordId;
        }
        this.saving = true;
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    async handleSuccess() {
        this.saving = false;
        this.showForm = false;
        this.editId = undefined;
        await refreshApex(this.wiredResult);
        this.toast('Team member saved', 'success');
    }

    handleError() {
        this.saving = false;
        this.toast('Could not save team member — check required fields', 'error');
    }

    async handleDelete(event) {
        try {
            await deleteRecord(event.currentTarget.dataset.id);
            await refreshApex(this.wiredResult);
            this.toast('Team member removed', 'success');
        } catch (e) {
            this.toast('Could not remove team member', 'error');
        }
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
