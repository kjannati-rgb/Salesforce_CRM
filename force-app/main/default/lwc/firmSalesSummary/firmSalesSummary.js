import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummary from '@salesforce/apex/FirmSalesSummaryController.getSummary';
import getGroupBreakdown from '@salesforce/apex/FirmSalesSummaryController.getGroupBreakdown';
import getOfficeBreakdown from '@salesforce/apex/FirmSalesSummaryController.getOfficeBreakdown';
import getOpportunities from '@salesforce/apex/FirmSalesSummaryController.getOpportunities';
import getView from '@salesforce/apex/FirmSalesSummaryController.getView';
import refreshFirm from '@salesforce/apex/FirmSalesSummaryController.refreshFirm';

const PAGE = 10;
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

export default class FirmSalesSummary extends LightningElement {
    @api recordId;

    period = 'alltime';
    business = 'all';
    summary;
    groups = [];          // persisted groups (default, no filters)
    offices = [];         // default office panel (no filters)
    view;                 // unified cross-filter result (getView) — present when any filter is active
    selOfficeId;
    selOfficeName;
    selGroup;
    drill;                // { rows, total, offset } — opps matching the active cross-filter
    refreshing = false;
    error;

    _summaryWire;
    _groupsWire;

    // ---------- persisted wires (instant default view) ----------
    @wire(getSummary, { firmId: '$recordId' })
    wiredSummary(result) {
        this._summaryWire = result;
        if (result.data) { this.summary = result.data; this.error = undefined; }
        else if (result.error) { this.error = this.msg(result.error); }
    }
    @wire(getGroupBreakdown, { firmId: '$recordId' })
    wiredGroups(result) {
        this._groupsWire = result;
        if (result.data) { this.groups = result.data; }
    }

    connectedCallback() { this.loadOffices(); }

    get filtersActive() { return !!(this.selOfficeId || this.selGroup || this.business !== 'all'); }
    get anySelection() { return !!(this.selOfficeId || this.selGroup); }
    get hasFilters() { return this.anySelection || this.business !== 'all'; }

    // ---------- data loads ----------
    loadOffices() {
        if (!this.recordId) return;
        getOfficeBreakdown({ firmId: this.recordId, period: this.period, businessType: 'all' })
            .then((rows) => { this.offices = rows || []; })
            .catch((e) => { this.error = this.msg(e); });
    }

    // recompute the linked view; if nothing is filtered, fall back to the persisted/default reads
    loadView() {
        if (!this.recordId) return;
        if (!this.filtersActive) { this.view = undefined; this.loadOffices(); return; }
        getView({
            firmId: this.recordId, period: this.period, businessType: this.business,
            officeId: this.selOfficeId || null, commercialGroup: this.selGroup || null
        }).then((vw) => { this.view = vw; }).catch((e) => { this.error = this.msg(e); });
    }

    // ---------- header ----------
    get firmName() { return this.summary ? this.summary.firmName : ''; }
    get lastRefreshed() { return this.summary ? this.summary.lastRefreshed : null; }
    get fxBasis() { return this.summary ? this.summary.fxBasis : 'Dated'; }
    get hasData() { return this.summary && this.summary.periods && this.summary.periods.length > 0; }

    get activePeriods() {
        if (this.view && this.view.periods) return this.view.periods;
        return this.summary ? this.summary.periods : null;
    }
    get currentPeriod() {
        const ps = this.activePeriods;
        if (!ps || !ps.length) return null;
        return ps.find((p) => p.key === this.period) || ps[0];
    }

    get lensNote() {
        const bits = [];
        if (this.business !== 'all') bits.push(this.business === 'new' ? 'new business' : 'renewals');
        if (this.selOfficeName) bits.push(this.selOfficeName);
        if (this.selGroup) bits.push(this.selGroup);
        return bits.length ? ' · ' + bits.join(' · ') : '';
    }

    get kpis() {
        const p = this.currentPeriod;
        if (!p || !this.summary) return [];
        const src = this.view || this.summary;
        const cancelVal = src.cancelValue, cancelCnt = src.cancelCount;
        const subs = this.view ? this.view.activeSubs : this.summary.activeSubs;
        const subVal = this.view ? this.view.activeSubValue : this.summary.activeSubValue;
        const card = (key, label, value, sub, neg) => ({ key, label, value, sub, valClass: neg ? 'k-val neg' : 'k-val' });
        return [
            card('net', 'Net Won Value (USD)', this.fmtUSD(p.netValue), 'net of cancellations' + this.lensNote, p.netValue < 0),
            card('won', 'Won Opportunities', this.fmtInt(p.wonCount), 'stage Closed Won' + this.lensNote, false),
            card('canc', 'Cancellations', this.fmtUSD(cancelVal), this.fmtInt(cancelCnt) + ' deals · all-time · already netted', cancelVal < 0),
            card('subs', 'Active Subscriptions', this.fmtInt(subs), this.fmtUSD(subVal) + ' active', false)
        ];
    }

    get yoy() {
        const ps = this.activePeriods;
        if (!ps || !ps.length) return null;
        const cfy = (ps.find((p) => p.key === 'cfy') || {}).netValue || 0;
        const pfy = (ps.find((p) => p.key === 'pfy') || {}).netValue || 0;
        const max = Math.max(Math.abs(cfy), Math.abs(pfy)) || 1;
        const delta = pfy ? ((cfy - pfy) / Math.abs(pfy)) * 100 : 0;
        const up = delta >= 0;
        return {
            cfyLabel: this.fmtUSD(cfy), pfyLabel: this.fmtUSD(pfy),
            cfyBarStyle: 'width:' + (Math.abs(cfy) / max * 100).toFixed(1) + '%',
            pfyBarStyle: 'width:' + (Math.abs(pfy) / max * 100).toFixed(1) + '%',
            up, deltaLabel: (up ? '▲ ' : '▼ ') + Math.abs(delta).toFixed(1) + '%',
            deltaClass: 'delta ' + (up ? 'up' : 'down')
        };
    }

    // ---------- panels ----------
    get groupRows() {
        const live = this.view && this.view.groups;
        const src = live ? this.view.groups : (this.groups || []);
        const rows = src.map((g) => {
            const v = live ? (g.value || 0) : this.valFor(g, 'Value');
            const items = live ? (g.items || 0) : this.valFor(g, 'Items');
            return { key: g.name, name: g.name, rawVal: v, value: this.fmtUSD(v), items: this.fmtInt(items), itemsCount: items };
        }).filter((r) => r.rawVal !== 0 || r.itemsCount !== 0);
        const total = rows.reduce((a, r) => a + Math.abs(r.rawVal), 0) || 1;
        rows.forEach((r) => {
            r.pct = (Math.abs(r.rawVal) / total * 100).toFixed(1);
            r.barStyle = 'width:' + r.pct + '%';
            r.selected = this.selGroup === r.key;
        });
        rows.sort((a, b) => b.rawVal - a.rawVal);
        return rows;
    }

    get officeRows() {
        const live = this.view && this.view.offices;
        const src = live ? this.view.offices : (this.offices || []);
        const rows = src.map((o) => ({
            key: o.officeId, id: o.officeId, name: o.officeName || '(no office)',
            location: [o.city, o.country].filter(Boolean).join(', ') || '—',
            rawVal: o.value, value: this.fmtUSD(o.value), won: this.fmtInt(o.wonCount), subs: o.subs,
            selected: this.selOfficeId === o.officeId
        }));
        rows.sort((a, b) => b.rawVal - a.rawVal);
        return rows;
    }

    valFor(g, kind) {
        const map = { alltime: 'allTime', cfy: 'cfy', pfy: 'pfy', t12m: 't12m' };
        const prefix = map[this.period] || 'allTime';
        return g[prefix + kind] || 0;
    }

    // ---------- toggles ----------
    get periodButtons() { return this.btns(['alltime|All-time', 'cfy|This FY', 'pfy|Last FY', 't12m|Last 12 mo'], this.period); }
    get businessButtons() { return this.btns(['all|All', 'new|New', 'renewal|Renewal'], this.business); }
    btns(defs, active) {
        return defs.map((d) => { const [key, label] = d.split('|'); return { key, label, pressed: key === active ? 'true' : 'false', cls: key === active ? 'tog on' : 'tog' }; });
    }
    handlePeriod(e) { this.period = e.currentTarget.dataset.key; this.reloadAll(); }
    handleBusiness(e) { this.business = e.currentTarget.dataset.key; this.reloadAll(); }
    reloadAll() { this.loadView(); if (this.anySelection) this.loadDrill(); }

    // ---------- cross-filter selection (linked widgets) ----------
    handleGroupSelect(e) {
        const name = e.currentTarget.dataset.name;
        this.selGroup = (this.selGroup === name) ? undefined : name;
        this.afterSelect();
    }
    handleOfficeSelect(e) {
        const id = e.currentTarget.dataset.id;
        const name = e.currentTarget.dataset.name;
        if (this.selOfficeId === id) { this.selOfficeId = undefined; this.selOfficeName = undefined; }
        else { this.selOfficeId = id; this.selOfficeName = name; }
        this.afterSelect();
    }
    handleRowKey(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.currentTarget.click(); } }
    afterSelect() {
        this.loadView();
        if (this.anySelection) { this.drill = { offset: 0 }; this.loadDrill(); }
        else { this.drill = undefined; }
    }
    clearFilters() {
        this.selOfficeId = undefined; this.selOfficeName = undefined; this.selGroup = undefined;
        this.business = 'all'; this.drill = undefined; this.loadView();
    }

    // ---------- drill: opps matching the active cross-filter ----------
    loadDrill() {
        if (!this.anySelection) { this.drill = undefined; return; }
        const offset = (this.drill && this.drill.offset) || 0;
        getOpportunities({
            firmId: this.recordId, officeId: this.selOfficeId || null, commercialGroup: this.selGroup || null,
            period: this.period, businessType: this.business, pageSize: PAGE, offset
        }).then((page) => {
            const rows = (page.rows || []).map((o) => ({
                id: o.id, name: o.name, officeName: o.officeName, closeDate: this.fmtDate(o.closeDate),
                type: o.type, stage: o.stage, amount: this.fmtFull(o.amountUSD),
                amtClass: o.amountUSD < 0 ? 'num neg' : 'num',
                badgeClass: o.stage === 'Closed Won - Cancellation' ? 'badge canc' : 'badge won'
            }));
            this.drill = { rows, total: page.total, offset };
        }).catch((e) => { this.error = this.msg(e); });
    }
    get drillInfo() {
        if (!this.drill) return '';
        if (!this.drill.total) return 'No opportunities';
        const start = this.drill.offset + 1;
        const end = Math.min(this.drill.offset + PAGE, this.drill.total);
        return start + '–' + end + ' of ' + this.fmtInt(this.drill.total) + ' opportunities';
    }
    get drillCtx() {
        const bits = [];
        if (this.selOfficeName) bits.push(this.selOfficeName + ' office');
        if (this.selGroup) bits.push(this.selGroup);
        if (this.business !== 'all') bits.push(this.business);
        return bits.length ? '— ' + bits.join(' · ') : '';
    }
    get prevDisabled() { return !this.drill || this.drill.offset <= 0; }
    get nextDisabled() { return !this.drill || (this.drill.offset + PAGE) >= this.drill.total; }
    handlePrev() { if (this.drill && this.drill.offset > 0) { this.drill.offset -= PAGE; this.loadDrill(); } }
    handleNext() { if (this.drill && (this.drill.offset + PAGE) < this.drill.total) { this.drill.offset += PAGE; this.loadDrill(); } }
    closeDrill() { this.clearFilters(); }

    // ---------- refresh ----------
    handleRefresh() {
        this.refreshing = true;
        refreshFirm({ firmId: this.recordId })
            .then(() => {
                this.toast('Recompute queued', 'Firm rollups are recomputing in the background.', 'success');
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                return new Promise((res) => setTimeout(res, 3000));
            })
            .then(() => Promise.all([refreshApex(this._summaryWire), refreshApex(this._groupsWire)]))
            .then(() => { this.loadView(); })
            .catch((e) => this.toast('Refresh failed', this.msg(e), 'error'))
            .finally(() => { this.refreshing = false; });
    }
    get refreshClass() { return this.refreshing ? 'btn spinning' : 'btn'; }

    // ---------- formatting ----------
    fmtUSD(n) {
        if (n === null || n === undefined) return '$0';
        const sign = n < 0 ? '-' : ''; const a = Math.abs(n);
        if (a >= 1e6) return sign + '$' + (a / 1e6).toFixed(2) + 'M';
        if (a >= 1e3) return sign + '$' + Math.round(a / 1e3) + 'K';
        return sign + '$' + Math.round(a);
    }
    fmtFull(n) { const sign = n < 0 ? '-' : ''; return sign + '$' + Math.round(Math.abs(n || 0)).toLocaleString('en-US'); }
    fmtInt(n) { return Math.round(n || 0).toLocaleString('en-US'); }
    fmtDate(d) {
        if (!d) return '';
        const parts = String(d).split('-');
        if (parts.length !== 3) return d;
        return parts[2] + ' ' + (MONTHS[parseInt(parts[1], 10) - 1] || '') + ' ' + parts[0];
    }
    msg(e) { return (e && e.body && e.body.message) ? e.body.message : (e && e.message) ? e.message : 'Unexpected error'; }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}
