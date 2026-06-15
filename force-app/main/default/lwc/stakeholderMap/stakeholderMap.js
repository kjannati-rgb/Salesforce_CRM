import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
    wiredResult;
    showForm = false;
    editId;
    saving = false;

    @wire(getStakeholders, { planId: '$recordId' })
    wiredStakeholders(result) {
        this.wiredResult = result;
        const { data, error } = result;
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

    get formTitle() {
        return this.editId ? 'Edit stakeholder' : 'New stakeholder';
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
            champ + ' champion' + (champ === 1 ? '' : 's') +
            ' · ' +
            detr + ' detractor' + (detr === 1 ? '' : 's')
        );
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
        this.toast('Stakeholder saved', 'success');
    }

    handleError() {
        this.saving = false;
        this.toast('Could not save stakeholder — check required fields', 'error');
    }

    async handleDelete(event) {
        try {
            await deleteRecord(event.currentTarget.dataset.id);
            await refreshApex(this.wiredResult);
            this.toast('Stakeholder removed', 'success');
        } catch (e) {
            this.toast('Could not remove stakeholder', 'error');
        }
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
