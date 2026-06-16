import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import REFRESH_CHANNEL from '@salesforce/messageChannel/AccountPlanRefresh__c';
import getMatrix from '@salesforce/apex/AccountPlanController.getMatrix';
import recalcHeadroom from '@salesforce/apex/AccountPlanController.recalcHeadroom';
import acceptSuggestion from '@salesforce/apex/ObjectiveSuggestionService.accept';

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

export default class WhitespaceMatrix extends LightningElement {
    @api recordId;
    matrix;
    error;
    recalculating = false;
    wiredResult;
    collapsed = []; // group keys currently collapsed
    subscription;

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

    get headroom() {
        return this.matrix ? this.fmt(this.matrix.headroom || 0) : '—';
    }

    get familySummary() {
        if (!this.matrix) return [];
        const owned = new Map();
        const gap = new Map();
        this.matrix.cells.forEach((c) => {
            owned.set(c.familyId, (owned.get(c.familyId) || 0) + (c.arr || 0));
            gap.set(c.familyId, (gap.get(c.familyId) || 0) + (c.expectedRevenue || 0));
        });
        return this.matrix.families.map((f) => {
            const g = gap.get(f.id) || 0;
            return {
                key: f.id,
                name: f.name,
                owned: this.fmt(owned.get(f.id) || 0),
                headroom: this.fmt(g),
                headroomNum: g,
                hasHeadroom: g > 0
            };
        });
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

    get rows() {
        if (!this.matrix) return [];
        const byNode = new Map();
        const order = [];
        this.matrix.cells.forEach((c) => {
            if (!byNode.has(c.nodeKey)) {
                byNode.set(c.nodeKey, {
                    key: c.nodeKey,
                    label: c.nodeLabel,
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
                    const amount =
                        c.arr != null && c.arr > 0
                            ? this.fmt(c.arr)
                            : c.expectedRevenue != null && c.expectedRevenue > 0
                            ? this.fmt(c.expectedRevenue)
                            : '—';
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
                officeUrl: node.officeAccountId ? '/' + node.officeAccountId : null,
                cells
            };
        });
    }

    handleToggleGroup(event) {
        const key = event.currentTarget.dataset.key;
        this.collapsed = this.collapsed.includes(key)
            ? this.collapsed.filter((k) => k !== key)
            : [...this.collapsed, key];
    }

    async handleRecalc() {
        this.recalculating = true;
        try {
            const count = await recalcHeadroom({ planId: this.recordId });
            await refreshApex(this.wiredResult);
            this.toast('Headroom recalculated', `${count} white-space cell${count === 1 ? '' : 's'} updated`, 'success');
        } catch (e) {
            this.toast('Recalculation failed', this.errMsg(e), 'error');
        } finally {
            this.recalculating = false;
        }
    }

    async handleCreateObjective(event) {
        const familyId = event.currentTarget.dataset.id;
        const fam = this.familySummary.find((f) => f.key === familyId);
        if (!fam || !fam.hasHeadroom) return;
        try {
            await acceptSuggestion({
                planId: this.recordId,
                title: `Convert ${fam.headroom} ${fam.name} white space`,
                targetAmount: fam.headroomNum,
                linkedFamilyId: familyId
            });
            publish(this.messageContext, REFRESH_CHANNEL, { planId: this.recordId });
            this.toast('Objective created', `${fam.name} — ${fam.headroom}`, 'success');
        } catch (e) {
            this.toast('Could not create objective', this.errMsg(e), 'error');
        }
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
