import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import bulkToggleField from '@salesforce/apex/EventSpeakerCockpitController.bulkToggleField';

import STATUS_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Speaker_Status__c';
import BIO_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Received_Bio__c';
import PHOTO_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Received_Photo__c';
import CAL_INVITE_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Sent_Calendar_Invite__c';
import BRIEFING_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Sent_Pre_Conference_Briefing__c';
import THANK_YOU_FIELD from '@salesforce/schema/Event_Speaker_Management__c.Sent_Thank_You_Email__c';

// Same five fields, same labels, same toggle cycle as the roster board's chip
// row (eventSpeakerRosterBoard) - this panel exists so a coordinator who
// clicked through to one record sees the identical visual language, not a
// second design.
const READINESS_FIELDS = [
    { apiName: 'Received_Bio__c', label: 'Bio' },
    { apiName: 'Received_Photo__c', label: 'Photo' },
    { apiName: 'Sent_Calendar_Invite__c', label: 'Cal. Invite' },
    { apiName: 'Sent_Pre_Conference_Briefing__c', label: 'Briefing' },
    { apiName: 'Sent_Thank_You_Email__c', label: 'Thank You' }
];

const TOGGLE_CYCLE = ['', 'Yes', 'No'];

const STATUS_STYLE = {
    Lead: { bg: '#f3f2f2', text: '#3e3e3c' },
    'No Response': { bg: '#f3f2f2', text: '#3e3e3c' },
    Pending: { bg: '#fef2dd', text: '#b98200' },
    Confirmed: { bg: '#e3f8ee', text: '#04844b' },
    Decline: { bg: '#fde9e9', text: '#ba0517' },
    Cancelled: { bg: '#fde9e9', text: '#ba0517' }
};

export default class SpeakerReadinessPanel extends LightningElement {
    @api recordId;
    record;
    wiredRecordResult;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [STATUS_FIELD, BIO_FIELD, PHOTO_FIELD, CAL_INVITE_FIELD, BRIEFING_FIELD, THANK_YOU_FIELD]
    })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        if (result.data) {
            this.record = result.data;
        }
    }

    get hasRecord() {
        return !!this.record;
    }

    get statusValue() {
        return this.record?.fields?.Speaker_Status__c?.value || '';
    }

    get statusStyle() {
        const style = STATUS_STYLE[this.statusValue] || STATUS_STYLE.Lead;
        return `background:${style.bg};color:${style.text}`;
    }

    get chips() {
        if (!this.record) {
            return [];
        }
        return READINESS_FIELDS.map((rf) => {
            const value = this.record.fields[rf.apiName]?.value || '';
            const isDone = value === 'Yes';
            const isNo = value === 'No';
            return {
                key: rf.apiName,
                label: rf.label,
                apiName: rf.apiName,
                value,
                iconName: isDone ? 'utility:check' : isNo ? 'utility:close' : null,
                chipClass: 'chip' + (isDone ? ' chip_done' : isNo ? ' chip_no' : '')
            };
        });
    }

    async handleChipClick(event) {
        const { apiname: apiName, value } = event.currentTarget.dataset;
        const currentIndex = TOGGLE_CYCLE.indexOf(value);
        const nextValue = TOGGLE_CYCLE[(currentIndex + 1) % TOGGLE_CYCLE.length];
        try {
            await bulkToggleField({ recordIds: [this.recordId], fieldApiName: apiName, newValue: nextValue });
            await refreshApex(this.wiredRecordResult);
        } catch (e) {
            const message = (e && e.body && e.body.message) ? e.body.message : 'Something went wrong.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
        }
    }
}
