import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummary from '@salesforce/apex/FirmSalesSummaryController.getSummary';
import getGroupBreakdown from '@salesforce/apex/FirmSalesSummaryController.getGroupBreakdown';
import getOfficeBreakdown from '@salesforce/apex/FirmSalesSummaryController.getOfficeBreakdown';
import getOpportunities from '@salesforce/apex/FirmSalesSummaryController.getOpportunities';
import getBusinessView from '@salesforce/apex/FirmSalesSummaryController.getBusinessView';
import refreshFirm from '@salesforce/apex/FirmSalesSummaryController.refreshFirm';

const PAGE = 10;
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

export default class FirmSalesSummary extends LightningElement {
    @api recordId;

    period = 'alltime';
    business = 'all';
    summary;
    groups = [];
    offices = [];
    businessView;          // live headline+groups when business !== 'all'; undefined for all-business
    drill;                 // { type, id, name, label, total, rows, offset, loading }
    refreshing = false;
    error;

    _summaryWire;
    _groupsWire;

    // ---------- wires (persisted, instant) ----------
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

    // ---------- live office breakdown ----------
    loadOffices() {
        if (!this.recordId) return;
        getOfficeBreakdown({ firmId: this.recordId, period: this.period, businessType: this.business })
            .then((rows) => { this.offices = rows || []; })
            .catch((e) => { this.error = this.msg(e); });
    }

    // ---------- header / KPIs ----------
    get firmName() { return this.summary ? this.summary.firmName : ''; }
    get lastRefreshed() { return this.summary ? this.summary.lastRefreshed : null; }
    get fxBasis() { return this.summary ? this.summary.fxBasis : 'Dated'; }
    get hasData() { return this.summary && this.summary.periods && this.summary.periods.length > 0; }

    // active period set: live business-lens view when New/Renewal is selected, else persisted summary
    get activePeriods() {
        if (this.businessView && this.businessView.periods) return this.businessView.periods;
        return this.summary ? this.summary.periods : null;
    }

    get currentPeriod() {
        const ps = this.activePeriods;
        if (!ps || !ps.length) return null;
        return ps.find((p) => p.key === this.period) || ps[0];
    }

    get kpis() {
        const p = this.currentPeriod;
        if (!p || !this.summary) return [];
        const s = this.summary;
        const bv = this.businessView;
        const cancelVal = bv ? bv.cancelValue : s.cancelValue;
        const cancelCnt = bv ? bv.cancelCount : s.cancelCount;
        const lens = this.business === 'all' ? '' : (this.business === 'new' ? ' · new business' : ' · renewals');
        const card = (key, label, value, sub, neg) => ({ key, label, value, sub, valClass: neg ? 'k-val neg' : 'k-val' });
        return [
            card('net', 'Net Won Value (USD)', this.fmtUSD(p.netValue), 'net of cancellations' + lens, p.netValue < 0),
            card('won', 'Won Opportunities', this.fmtInt(p.wonCount), 'stage Closed Won' + lens, false),
            card('canc', 'Cancellations', this.fmtUSD(cancelVal), this.fmtInt(cancelCnt) + ' deals · all-time · already netted', cancelVal < 0),
            card('subs', 'Active Subscriptions', this.fmtInt(s.activeSubs), this.fmtUSD(s.activeSubValue) + ' active', false)
        ];
    }

    // ---------- YoY ----------
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

    // ---------- group rows (persisted by period; live flat value/items in a business lens) ----------
    get groupRows() {
        const live = this.businessView && this.businessView.groups;
        const src = live ? this.businessView.groups : (this.groups || []);
        const rows = src.map((g) => {
            const v = live ? (g.value || 0) : this.valFor(g, 'Value');
            const items = live ? (g.items || 0) : this.valFor(g, 'Items');
            return { key: g.name, name: g.name, rawVal: v, value: this.fmtUSD(v), items: this.fmtInt(items), itemsCount: items };
        }).filter((r) => r.rawVal !== 0 || r.itemsCount !== 0);
        const total = rows.reduce((a, r) => a + Math.abs(r.rawVal), 0) || 1;
        rows.forEach((r) => {
            r.pct = (Math.abs(r.rawVal) / total * 100).toFixed(1);
            r.barStyle = 'width:' + r.pct + '%';
            r.selected = this.drill && this.drill.type === 'group' && this.drill.name === r.key;
        });
        rows.sort((a, b) => b.rawVal - a.rawVal);
        return rows;
    }

    get officeRows() {
        const rows = (this.offices || []).map((o) => ({
            key: o.officeId, id: o.officeId, name: o.officeName || '(no office)',
            location: [o.city, o.country].filter(Boolean).join(', ') || '—',
            rawVal: o.value, value: this.fmtUSD(o.value), won: this.fmtInt(o.wonCount), subs: o.subs,
            selected: this.drill && this.drill.type === 'office' && this.drill.id === o.officeId
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

    handlePeriod(e) {
        this.period = e.currentTarget.dataset.key;
        if (this.drill) { this.drill.offset = 0; this.loadDrill(); }
        this.loadOffices();
        this.loadBusinessView();
    }
    handleBusiness(e) {
        this.business = e.currentTarget.dataset.key;
        if (this.drill) { this.drill.offset = 0; this.loadDrill(); }
        this.loadOffices();
        this.loadBusinessView();
    }

    // live recompute of headline + groups for the New/Renewal lens (all-business uses persisted)
    loadBusinessView() {
        if (!this.recordId || this.business === 'all') { this.businessView = undefined; return; }
        getBusinessView({ firmId: this.recordId, period: this.period, businessType: this.business })
            .then((bv) => { this.businessView = bv; })
            .catch((e) => { this.error = this.msg(e); });
    }

    // ---------- drill ----------
    handleRowClick(e) {
        const tr = e.currentTarget;
        const type = tr.dataset.type;
        const name = tr.dataset.name;
        const id = tr.dataset.id;
        this.drill = { type, name, id, offset: 0, total: 0, rows: [], loading: true,
            label: type === 'group' ? name : (name + ' office') };
        this.loadDrill();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => { const el = this.template.querySelector('.drill'); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); });
    }
    handleRowKey(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); this.handleRowClick(e); } }

    loadDrill() {
        if (!this.drill) return;
        this.drill = { ...this.drill, loading: true };
        getOpportunities({
            firmId: this.recordId,
            officeId: this.drill.type === 'office' ? this.drill.id : null,
            commercialGroup: this.drill.type === 'group' ? this.drill.name : null,
            period: this.period, businessType: this.business,
            pageSize: PAGE, offset: this.drill.offset
        }).then((page) => {
            const rows = (page.rows || []).map((o) => ({
                id: o.id, name: o.name, officeName: o.officeName,
                closeDate: this.fmtDate(o.closeDate), type: o.type, stage: o.stage,
                amount: this.fmtFull(o.amountUSD), amtClass: o.amountUSD < 0 ? 'num neg' : 'num',
                isCanc: o.stage === 'Closed Won - Cancellation',
                badgeClass: o.stage === 'Closed Won - Cancellation' ? 'badge canc' : 'badge won'
            }));
            this.drill = { ...this.drill, rows, total: page.total, loading: false };
        }).catch((e) => { this.error = this.msg(e); this.drill = { ...this.drill, loading: false }; });
    }

    get drillInfo() {
        if (!this.drill) return '';
        if (!this.drill.total) return 'No opportunities';
        const start = this.drill.offset + 1;
        const end = Math.min(this.drill.offset + PAGE, this.drill.total);
        return start + '–' + end + ' of ' + this.fmtInt(this.drill.total) + ' opportunities';
    }
    get drillCtx() {
        if (!this.drill) return '';
        const pl = (this.currentPeriod || {}).label || '';
        return '— ' + this.drill.label + ' · ' + pl + (this.business === 'all' ? '' : ' · ' + this.business);
    }
    get prevDisabled() { return !this.drill || this.drill.offset <= 0; }
    get nextDisabled() { return !this.drill || (this.drill.offset + PAGE) >= this.drill.total; }
    handlePrev() { if (this.drill && this.drill.offset > 0) { this.drill.offset -= PAGE; this.loadDrill(); } }
    handleNext() { if (this.drill && (this.drill.offset + PAGE) < this.drill.total) { this.drill.offset += PAGE; this.loadDrill(); } }
    closeDrill() { this.drill = undefined; }

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
            .then(() => this.loadOffices())
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
        const parts = String(d).split('-'); // YYYY-MM-DD
        if (parts.length !== 3) return d;
        return parts[2] + ' ' + (MONTHS[parseInt(parts[1], 10) - 1] || '') + ' ' + parts[0];
    }
    msg(e) { return (e && e.body && e.body.message) ? e.body.message : (e && e.message) ? e.message : 'Unexpected error'; }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}
