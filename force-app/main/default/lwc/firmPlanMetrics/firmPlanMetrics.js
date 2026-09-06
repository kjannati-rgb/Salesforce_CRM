import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getSummary from '@salesforce/apex/FirmSalesSummaryController.getSummary';
import getOpenPipeline from '@salesforce/apex/FirmSalesSummaryController.getOpenPipeline';

const PLAN_ACCOUNT = 'AccountPlan.AccountId';
const STAGE_ROWS = 4;

/**
 * Firm-grain replacement for the standard Account Plan "Account Metrics" strip.
 * The native strip only counts opportunities directly on the plan's account, so it reads
 * £0 for firms whose revenue lives on office opportunities. This one aggregates via
 * Opportunity.Ultimate_Account__c — same engine as the Firm Sales Summary — in USD.
 * Styled with SLDS only (no custom skin) so it blends with the native plan page.
 */
export default class FirmPlanMetrics extends NavigationMixin(LightningElement) {
    @api recordId;          // AccountPlan id (record page)
    firmId;
    summary;
    pipe;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [PLAN_ACCOUNT] })
    wiredPlan({ data, error }) {
        if (data) { this.firmId = data.fields.AccountId.value; this.error = undefined; }
        else if (error) { this.error = this.msg(error); }
    }

    @wire(getSummary, { firmId: '$firmId' })
    wiredSummary({ data, error }) {
        if (data) { this.summary = data; this.error = undefined; }
        else if (error) { this.error = this.msg(error); }
    }

    @wire(getOpenPipeline, { firmId: '$firmId' })
    wiredPipe({ data, error }) {
        if (data) { this.pipe = data; this.error = undefined; }
        else if (error) { this.error = this.msg(error); }
    }

    get ready() { return !!(this.summary && this.pipe); }
    get firmName() { return this.summary ? this.summary.firmName : ''; }

    period(key) {
        if (!this.summary || !this.summary.periods) return {};
        return this.summary.periods.find((p) => p.key === key) || {};
    }

    // ---- open pipeline (donut stand-in) ----
    get openTotal() { return this.fmtInt(this.pipe.openCount); }
    get openValue() { return this.fmtUSD(this.pipe.openValueUSD); }
    get stageRows() {
        return (this.pipe.byStage || []).slice(0, STAGE_ROWS)
            .map((s) => ({ name: s.stage, count: this.fmtInt(s.count) }));
    }
    get moreStages() { return Math.max(0, (this.pipe.byStage || []).length - STAGE_ROWS); }

    // ---- revenue / win rate / acv / subs ----
    get revLast() { return this.fmtUSD(this.period('pfy').netValue); }
    get revThis() { return this.fmtUSD(this.period('cfy').netValue); }
    get winLast() { return this.rate(this.pipe.pfyWinRate); }
    get winThis() { return this.rate(this.pipe.cfyWinRate); }
    get winLastSub() { return 'Last FY (' + this.fmtInt(this.pipe.pfyClosedCount) + ' closed)'; }
    get winThisSub() { return 'This FY (' + this.fmtInt(this.pipe.cfyClosedCount) + ' closed)'; }
    get acvThis() { return this.fmtUSD(this.period('cfy').acv); }
    get subsCount() { return this.fmtInt(this.summary.activeSubs); }
    get subsSub() { return this.fmtUSD(this.summary.activeSubValue) + ' active · CPQ only'; }

    goToFirm() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.firmId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    rate(r) { return (r === null || r === undefined) ? '—' : r + '%'; }
    fmtUSD(n) {
        if (n === null || n === undefined) return '$0';
        const sign = n < 0 ? '-' : ''; const a = Math.abs(n);
        if (a >= 1e6) return sign + '$' + (a / 1e6).toFixed(2) + 'M';
        if (a >= 1e3) return sign + '$' + Math.round(a / 1e3) + 'K';
        return sign + '$' + Math.round(a);
    }
    fmtInt(n) { return Math.round(n || 0).toLocaleString('en-US'); }
    msg(e) { return (e && e.body && e.body.message) ? e.body.message : (e && e.message) ? e.message : 'Unexpected error'; }
}
