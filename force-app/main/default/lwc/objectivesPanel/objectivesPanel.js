import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
    wiredResult;
    showForm = false;
    editId; // undefined = create, otherwise the objective being edited
    saving = false;

    @wire(getObjectives, { planId: '$recordId' })
    wiredObjectives(result) {
        this.wiredResult = result;
        const { data, error } = result;
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

    get formTitle() {
        return this.editId ? 'Edit objective' : 'New objective';
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
                barStyle: 'width:' + pct + '%',
                notDone: o.status !== 'Done'
            };
        });
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
            fields.Account_Plan__c = this.recordId; // parent the new objective to this plan
        }
        this.saving = true;
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    async handleSuccess() {
        this.saving = false;
        this.showForm = false;
        this.editId = undefined;
        await refreshApex(this.wiredResult);
        this.toast('Objective saved', 'success');
    }

    handleError() {
        this.saving = false;
        this.toast('Could not save objective — check required fields', 'error');
    }

    async handleComplete(event) {
        const id = event.currentTarget.dataset.id;
        try {
            await updateRecord({ fields: { Id: id, Status__c: 'Done', Progress_Pct__c: 100 } });
            await refreshApex(this.wiredResult);
            this.toast('Objective completed', 'success');
        } catch (e) {
            this.toast('Could not complete objective', 'error');
        }
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
