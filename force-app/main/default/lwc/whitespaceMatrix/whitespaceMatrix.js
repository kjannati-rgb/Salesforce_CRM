import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import REFRESH_CHANNEL from '@salesforce/messageChannel/AccountPlanRefresh__c';
import getMatrix from '@salesforce/apex/AccountPlanController.getMatrix';

const STATE_CLASS = {
    Owned_Healthy: 'cell c-owned',
    In_Renewal: 'cell c-renewal',
    Win_Back: 'cell c-winback',
    White_Space: 'cell c-white',
    Booked: 'cell c-booked',
    Candidate: 'cell c-candidate',
    No_Engagement: 'cell c-noeng',
    NA: 'cell c-na'
};

const STATE_LABEL = {
    Owned_Healthy: 'Owned',
    In_Renewal: 'In Renewal',
    Win_Back: 'Win-back',
    White_Space: 'White space',
    Booked: 'Booked',
    Candidate: 'Candidate',
    No_Engagement: 'No engage',
    NA: 'n/a'
};

// Fixed display order for the "By Region" view — anything unmapped (Unclassified) sorts last.
const REGION_ORDER = ['EMEA', 'Middle East & Africa', 'North America', 'APAC', 'LATAM'];

export default class WhitespaceMatrix extends LightningElement {
    @api recordId;
    matrix;
    error;
    wiredResult;
    collapsed = []; // group keys currently collapsed
    subscription;
    viewMode = 'office'; // 'office' | 'region' | 'firm'

    @wire(MessageContext)
    messageContext;

    @wire(getMatrix, { planId: '$recordId' })
    wiredMatrix(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.matrix = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.matrix = undefined;
        }
    }

    connectedCallback() {
        this.subscription = subscribe(this.messageContext, REFRESH_CHANNEL, (msg) => {
            if (!msg || msg.planId === this.recordId) {
                refreshApex(this.wiredResult);
            }
        });
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    get hasData() {
        return this.matrix && this.matrix.families && this.matrix.families.length > 0;
    }

    get subtitle() {
        if (!this.matrix) return '';
        return [this.matrix.segment, this.matrix.tier, this.matrix.dealModel, this.matrix.accountName]
            .filter((p) => p)
            .join(' · ');
    }

    get totalArr() {
        return this.matrix ? this.fmt(this.matrix.totalArr || 0) : '—';
    }

    get familySummary() {
        if (!this.matrix) return [];
        const owned = new Map();
        this.matrix.cells.forEach((c) => {
            owned.set(c.familyId, (owned.get(c.familyId) || 0) + (c.arr || 0));
        });
        return this.matrix.families.map((f) => ({
            key: f.id,
            name: f.name,
            owned: this.fmt(owned.get(f.id) || 0)
        }));
    }

    // Ordered group bands (families arrive group-ordered from the controller).
    get bands() {
        if (!this.matrix) return [];
        const out = [];
        let cur = null;
        this.matrix.families.forEach((f) => {
            const key = f.groupId || 'none';
            if (!cur || cur.key !== key) {
                cur = { key, label: f.groupName || 'Ungrouped', isGroup: !!f.groupId, fams: [] };
                out.push(cur);
            }
            cur.fams.push({ id: f.id, name: f.name });
        });
        return out.map((b) => {
            const isCollapsed = b.isGroup && this.collapsed.includes(b.key);
            return {
                key: b.key,
                label: b.label,
                isGroup: b.isGroup,
                collapsed: isCollapsed,
                count: b.fams.length,
                colspan: isCollapsed ? 1 : b.fams.length,
                toggleIcon: isCollapsed ? 'utility:chevronright' : 'utility:chevrondown',
                showToggle: b.isGroup
            };
        });
    }

    // Flat column list aligned to the rendered table (collapsed band = one placeholder column).
    get visibleColumns() {
        if (!this.matrix) return [];
        const cols = [];
        this.bands.forEach((b) => {
            if (b.collapsed) {
                cols.push({ key: 'col-' + b.key, collapsed: true, name: b.count + ' hidden' });
            } else {
                this.matrix.families
                    .filter((f) => (f.groupId || 'none') === b.key)
                    .forEach((f) =>
                        cols.push({ key: f.id, familyId: f.id, collapsed: false, name: f.name })
                    );
            }
        });
        return cols;
    }

    get isFirmView() {
        return this.viewMode === 'firm';
    }

    get isRegionView() {
        return this.viewMode === 'region';
    }

    get officeViewVariant() {
        return this.viewMode === 'office' ? 'brand' : 'neutral';
    }

    get regionViewVariant() {
        return this.isRegionView ? 'brand' : 'neutral';
    }

    get firmViewVariant() {
        return this.isFirmView ? 'brand' : 'neutral';
    }

    handleViewOffice() {
        this.viewMode = 'office';
    }

    handleViewRegion() {
        this.viewMode = 'region';
    }

    handleViewFirm() {
        this.viewMode = 'firm';
    }

    get rows() {
        if (this.isFirmView) return this.firmRows;
        if (this.isRegionView) return this.regionRows;
        return this.officeRows;
    }

    get officeRows() {
        if (!this.matrix) return [];
        const byNode = new Map();
        const order = [];
        this.matrix.cells.forEach((c) => {
            if (!byNode.has(c.nodeKey)) {
                byNode.set(c.nodeKey, {
                    key: c.nodeKey,
                    label: c.nodeLabel,
                    region: c.nodeRegion,
                    officeAccountId: c.officeAccountId,
                    cells: new Map()
                });
                order.push(c.nodeKey);
            }
            byNode.get(c.nodeKey).cells.set(c.familyId, c);
        });
        const cols = this.visibleColumns;
        return order.map((k) => {
            const node = byNode.get(k);
            const cells = cols.map((col) => {
                if (col.collapsed) {
                    return { key: 'x-' + k + '-' + col.key, cssClass: 'cell c-collapsed', amount: '⋯', sub: '' };
                }
                const c = node.cells.get(col.familyId);
                if (c) {
                    const amount = c.arr != null && c.arr > 0 ? this.fmt(c.arr) : '—';
                    return {
                        key: k + '-' + col.familyId,
                        cssClass: STATE_CLASS[c.state] || 'cell c-na',
                        amount,
                        sub: STATE_LABEL[c.state] || ''
                    };
                }
                return { key: k + '-' + col.familyId, cssClass: 'cell c-na', amount: 'n/a', sub: '' };
            });
            return {
                key: k,
                label: node.label,
                region: node.region,
                officeUrl: node.officeAccountId ? '/' + node.officeAccountId : null,
                cells
            };
        });
    }

    // One row per macro region (EMEA / Middle East & Africa / North America / APAC / LATAM), each
    // summing every office node that falls in it — a middle granularity between one-row-per-office
    // and one-row-total.
    get regionRows() {
        if (!this.matrix) return [];
        const byRegion = new Map(); // region -> { officeCount, byFamily: Map<familyId, arr> }
        const nodesSeenByRegion = new Map(); // region -> Set<nodeKey>
        this.matrix.cells.forEach((c) => {
            const region = c.continent || 'Unclassified';
            if (!byRegion.has(region)) {
                byRegion.set(region, new Map());
                nodesSeenByRegion.set(region, new Set());
            }
            nodesSeenByRegion.get(region).add(c.nodeKey);
            const byFamily = byRegion.get(region);
            const agg = byFamily.get(c.familyId) || { arr: 0 };
            agg.arr += c.arr || 0;
            byFamily.set(c.familyId, agg);
        });

        const regions = [...byRegion.keys()].sort((a, b) => {
            const ia = REGION_ORDER.indexOf(a);
            const ib = REGION_ORDER.indexOf(b);
            if (ia === -1 && ib === -1) return a.localeCompare(b);
            if (ia === -1) return 1;
            if (ib === -1) return -1;
            return ia - ib;
        });

        const cols = this.visibleColumns;
        return regions.map((region) => {
            const byFamily = byRegion.get(region);
            const officeCount = nodesSeenByRegion.get(region).size;
            const cells = cols.map((col) => {
                if (col.collapsed) {
                    return { key: 'rg-x-' + region + '-' + col.key, cssClass: 'cell c-collapsed', amount: '⋯', sub: '' };
                }
                const agg = byFamily.get(col.familyId);
                if (agg) {
                    const owned = agg.arr > 0;
                    const state = owned ? 'Owned_Healthy' : 'White_Space';
                    const amount = owned ? this.fmt(agg.arr) : '—';
                    return {
                        key: 'rg-' + region + '-' + col.familyId,
                        cssClass: STATE_CLASS[state] || 'cell c-na',
                        amount,
                        sub: STATE_LABEL[state] || ''
                    };
                }
                return { key: 'rg-' + region + '-' + col.familyId, cssClass: 'cell c-na', amount: 'n/a', sub: '' };
            });
            return {
                key: 'region-' + region,
                label: region,
                region: officeCount + (officeCount === 1 ? ' office' : ' offices') + ' combined',
                officeUrl: null,
                cells
            };
        });
    }

    // Single aggregated row summing every office node per family — no office breakdown.
    get firmRows() {
        if (!this.matrix) return [];
        const byFamily = new Map();
        const nodeKeys = new Set();
        this.matrix.cells.forEach((c) => {
            nodeKeys.add(c.nodeKey);
            const agg = byFamily.get(c.familyId) || { arr: 0 };
            agg.arr += c.arr || 0;
            byFamily.set(c.familyId, agg);
        });
        const cols = this.visibleColumns;
        const cells = cols.map((col) => {
            if (col.collapsed) {
                return { key: 'firm-x-' + col.key, cssClass: 'cell c-collapsed', amount: '⋯', sub: '' };
            }
            const agg = byFamily.get(col.familyId);
            if (agg) {
                const owned = agg.arr > 0;
                const state = owned ? 'Owned_Healthy' : 'White_Space';
                const amount = owned ? this.fmt(agg.arr) : '—';
                return {
                    key: 'firm-' + col.familyId,
                    cssClass: STATE_CLASS[state] || 'cell c-na',
                    amount,
                    sub: STATE_LABEL[state] || ''
                };
            }
            return { key: 'firm-' + col.familyId, cssClass: 'cell c-na', amount: 'n/a', sub: '' };
        });
        return [
            {
                key: 'firm-total',
                label: this.matrix.accountName || 'Firm total',
                region: nodeKeys.size + (nodeKeys.size === 1 ? ' office' : ' offices') + ' combined',
                officeUrl: null,
                cells
            }
        ];
    }

    handleToggleGroup(event) {
        const key = event.currentTarget.dataset.key;
        this.collapsed = this.collapsed.includes(key)
            ? this.collapsed.filter((k) => k !== key)
            : [...this.collapsed, key];
    }

    errMsg(e) {
        return e && e.body && e.body.message ? e.body.message : 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    fmt(n) {
        if (n >= 1000000) return '£' + (n / 1000000).toFixed(2) + 'M';
        if (n >= 1000) return '£' + Math.round(n / 1000) + 'K';
        return '£' + n;
    }
}
