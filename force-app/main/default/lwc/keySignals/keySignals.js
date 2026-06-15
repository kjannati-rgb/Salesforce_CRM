import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSignals from '@salesforce/apex/AccountPlanController.getSignals';

const SEV_CLASS = { High: 'dot r', Medium: 'dot o', Low: 'dot g' };

export default class KeySignals extends LightningElement {
    @api recordId;
    signals = [];
    error;
    wiredResult;
    showForm = false;
    editId;
    saving = false;

    @wire(getSignals, { planId: '$recordId' })
    wiredSignals(result) {
        this.wiredResult = result;
        const { data, error } = result;
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

    get formTitle() {
        return this.editId ? 'Edit signal' : 'New signal';
    }

    get items() {
        return this.signals.map((s) => ({
            id: s.id,
            dotClass: SEV_CLASS[s.severity] || 'dot o',
            summary: s.summary,
            recommendedAction: s.recommendedAction,
            meta: [s.source, s.severity, s.signalType].filter((p) => p).join(' · ')
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
        this.toast('Signal saved', 'success');
    }

    handleError() {
        this.saving = false;
        this.toast('Could not save signal — check required fields', 'error');
    }

    async setStatus(id, status, message) {
        try {
            await updateRecord({ fields: { Id: id, Status__c: status } });
            await refreshApex(this.wiredResult);
            this.toast(message, 'success');
        } catch (e) {
            this.toast('Could not update signal', 'error');
        }
    }

    handleActioned(event) {
        this.setStatus(event.currentTarget.dataset.id, 'Actioned', 'Signal marked actioned');
    }

    handleDismiss(event) {
        this.setStatus(event.currentTarget.dataset.id, 'Dismissed', 'Signal dismissed');
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
