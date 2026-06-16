import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, MessageContext } from 'lightning/messageService';
import REFRESH_CHANNEL from '@salesforce/messageChannel/AccountPlanRefresh__c';
import getColumnConfig from '@salesforce/apex/AccountPlanController.getColumnConfig';

export default class WhitespaceColumns extends LightningElement {
    @api recordId;
    config = [];
    wiredResult;
    showFamilyForm = false;
    showGroupForm = false;
    editId; // undefined = new
    saving = false;

    @wire(MessageContext)
    messageContext;

    @wire(getColumnConfig)
    wiredConfig(result) {
        this.wiredResult = result;
        if (result.data) {
            this.config = result.data;
        } else if (result.error) {
            this.config = [];
        }
    }

    get items() {
        return this.config.map((c) => ({
            id: c.id,
            name: c.name,
            active: c.active,
            group: c.groupName || '—',
            relevance:
                [c.relevantLawFirm ? 'Law' : null, c.relevantCorporate ? 'Corp' : null]
                    .filter((x) => x)
                    .join(' / ') || '—',
            rowClass: c.active ? 'col' : 'col off',
            toggleIcon: c.active ? 'utility:toggle_on' : 'utility:toggle_off',
            toggleTitle: c.active ? 'Remove from matrix' : 'Add to matrix'
        }));
    }

    async handleToggleActive(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.config.find((c) => c.id === id);
        try {
            await updateRecord({ fields: { Id: id, Active__c: !cur.active } });
            await refreshApex(this.wiredResult);
            publish(this.messageContext, REFRESH_CHANNEL, { planId: this.recordId });
            this.toast(cur.active ? 'Removed from matrix' : 'Added to matrix', 'success');
        } catch (e) {
            this.toast('Could not update product', 'error');
        }
    }

    handleNewProduct() {
        this.editId = undefined;
        this.showFamilyForm = true;
        this.showGroupForm = false;
    }

    handleEdit(event) {
        this.editId = event.currentTarget.dataset.id;
        this.showFamilyForm = true;
        this.showGroupForm = false;
    }

    handleNewGroup() {
        this.editId = undefined;
        this.showGroupForm = true;
        this.showFamilyForm = false;
    }

    handleCancel() {
        this.showFamilyForm = false;
        this.showGroupForm = false;
        this.editId = undefined;
    }

    handleSubmit() {
        this.saving = true; // let the record-edit-form proceed
    }

    async handleSuccess() {
        this.saving = false;
        this.showFamilyForm = false;
        this.showGroupForm = false;
        this.editId = undefined;
        await refreshApex(this.wiredResult);
        publish(this.messageContext, REFRESH_CHANNEL, { planId: this.recordId });
        this.toast('Saved', 'success');
    }

    handleError() {
        this.saving = false;
        this.toast('Could not save — check required fields', 'error');
    }

    get familyFormTitle() {
        return this.editId ? 'Edit product' : 'New product';
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
