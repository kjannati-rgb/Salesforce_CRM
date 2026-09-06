import { LightningElement, api, wire } from 'lwc';
import { getRecord, updateRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getCoverageConfig from '@salesforce/apex/LexProCoverageController.getCoverageConfig';
import ID from '@salesforce/schema/Opportunity.Id';
import STAGE from '@salesforce/schema/Opportunity.StageName';
import TEAM from '@salesforce/schema/Opportunity.Opportunity_Owner_Team__c';
import RTDEV from '@salesforce/schema/Opportunity.RecordType.DeveloperName';
import JUR from '@salesforce/schema/Opportunity.LexPRO_Qual_Jurisdiction_Coverage__c';
import CON from '@salesforce/schema/Opportunity.LexPRO_Qual_Content_Coverage__c';
import PRC from '@salesforce/schema/Opportunity.LexPRO_Qual_Process_Improvement__c';
import JURS from '@salesforce/schema/Opportunity.LexPRO_Qual_Jurisdictions__c';
import JUROTHER from '@salesforce/schema/Opportunity.LexPRO_Qual_Jurisdiction_Other__c';
import WAREAS from '@salesforce/schema/Opportunity.LexPRO_Qual_Work_Areas__c';
import WAOTHER from '@salesforce/schema/Opportunity.LexPRO_Qual_Work_Area_Other__c';
import PRCOTHER from '@salesforce/schema/Opportunity.LexPRO_Qual_Process_Other__c';

const FIELDS = [ID, STAGE, TEAM, RTDEV, JUR, CON, PRC, JURS, JUROTHER, WAREAS, WAOTHER, PRCOTHER];

/**
 * REV-69 — LexPRO Deal Qualifier (container).
 * Stateful host: owns the record + coverage config, derives completeness/fit,
 * persists via LDS updateRecord and lets the LexPRO_NB_Qualification_Gate
 * validation rule enforce server-side. Children are presentational and stateless.
 */
export default class LexproQualifier extends LightningElement {
    @api recordId;
    @api variant = 'embedded'; // 'embedded' | 'modal'

    regions = [];
    workAreas = [];

    lValue;            // Jurisdiction coverage  Yes|No
    eValue;            // Content coverage        Yes|No
    xValues = [];      // Process improvement     multi-select

    lRegions = [];     // selected region labels (incl. "Other")
    lOther = '';       // jurisdiction "Other" detail
    eAreas = [];       // selected work-area labels (incl. "Other")
    eOther = '';       // work-area "Other" detail
    xOther = '';       // process "Other" detail

    submitted = false;
    _seeded = false;

    @wire(getCoverageConfig)
    wiredConfig({ data, error }) {
        if (data) {
            this.regions = data.filter((r) => r.Type__c === 'Region');
            this.workAreas = data.filter((r) => r.Type__c === 'WorkArea');
        } else if (error) {
            // Surface it — a silent failure here renders as an empty map/work-area list
            // with no clue why (e.g. missing Apex class access on the assigned permission set).
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Coverage details unavailable',
                    message: this.friendlyError(error),
                    variant: 'error'
                })
            );
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        // Seed prior answers once so re-opening shows existing state.
        if (data && !this._seeded) {
            const jur = getFieldValue(data, JUR);
            const con = getFieldValue(data, CON);
            const prc = getFieldValue(data, PRC);
            const jurs = getFieldValue(data, JURS);
            const jurother = getFieldValue(data, JUROTHER);
            const wareas = getFieldValue(data, WAREAS);
            const waother = getFieldValue(data, WAOTHER);
            const prcother = getFieldValue(data, PRCOTHER);
            if (jur) this.lValue = jur;
            if (con) this.eValue = con;
            if (prc) this.xValues = prc.split(';');
            if (jurs) this.lRegions = jurs.split(';');
            if (jurother) this.lOther = jurother;
            if (wareas) this.eAreas = wareas.split(';');
            if (waother) this.eOther = waother;
            if (prcother) this.xOther = prcother;
            this._seeded = true;
        }
    }

    handleResolve(event) {
        const d = event.detail;
        if (d.field === 'L') {
            this.lValue = d.value;
            this.lRegions = d.regions || [];
            this.lOther = d.other || '';
        } else if (d.field === 'E') {
            this.eValue = d.value;
            this.eAreas = d.areas || [];
            this.eOther = d.other || '';
        } else if (d.field === 'X') {
            this.xValues = d.values || [];
            this.xOther = d.other || '';
        }
    }

    get count() {
        let c = 0;
        if (this.lValue) c += 1;
        if (this.eValue) c += 1;
        if (this.xValues && this.xValues.length) c += 1;
        return c;
    }

    get complete() {
        return this.count === 3;
    }

    get fit() {
        if (!this.lValue || !this.eValue) return 'Pending';
        if (this.lValue === 'Yes' && this.eValue === 'Yes') return 'Strong';
        if (this.lValue === 'No' && this.eValue === 'No') return 'Caution';
        return 'Moderate';
    }

    get rootClass() {
        return this.variant === 'modal' ? 'lex-root lex-root_modal' : 'lex-root';
    }

    async handleAdvance() {
        const fields = {};
        fields[ID.fieldApiName] = this.recordId;
        fields[JUR.fieldApiName] = this.lValue;
        fields[CON.fieldApiName] = this.eValue;
        fields[PRC.fieldApiName] = (this.xValues || []).join(';'); // multi-select = semicolon-joined
        fields[JURS.fieldApiName] = (this.lRegions || []).join(';');
        fields[JUROTHER.fieldApiName] = this.lOther || '';
        fields[WAREAS.fieldApiName] = (this.eAreas || []).join(';');
        fields[WAOTHER.fieldApiName] = this.eOther || '';
        fields[PRCOTHER.fieldApiName] = this.xOther || '';
        fields[STAGE.fieldApiName] = 'Qualify';
        try {
            await updateRecord({ fields });
            this.submitted = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Moved to Qualify',
                    message: 'Qualification saved to the opportunity.',
                    variant: 'success'
                })
            );
            // Closes the quick-action modal; harmless no-op when embedded on the page.
            this.closeModal();
        } catch (e) {
            // Validation-rule / FLS errors surface here as direction, never "validation failed".
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not advance',
                    message: this.friendlyError(e),
                    variant: 'error'
                })
            );
        }
    }

    friendlyError(e) {
        return (
            (e &&
                e.body &&
                e.body.output &&
                e.body.output.errors &&
                e.body.output.errors[0] &&
                e.body.output.errors[0].message) ||
            (e && e.body && e.body.message) ||
            'Please try again.'
        );
    }

    closeModal() {
        // No-op outside an action context; closes the quick-action modal when in one.
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
