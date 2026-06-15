import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMatrix from '@salesforce/apex/AccountPlanController.getMatrix';
import recalcHeadroom from '@salesforce/apex/AccountPlanController.recalcHeadroom';

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

    get hasData() {
        return this.matrix && this.matrix.families && this.matrix.families.length > 0;
    }

    get subtitle() {
        if (!this.matrix) return '';
        const parts = [
            this.matrix.segment,
            this.matrix.tier,
            this.matrix.dealModel,
            this.matrix.accountName
        ].filter((p) => p);
        return parts.join(' · ');
    }

    get totalArr() {
        return this.matrix ? this.fmt(this.matrix.totalArr || 0) : '—';
    }

    get headroom() {
        return this.matrix ? this.fmt(this.matrix.headroom || 0) : '—';
    }

    // Per-family Owned vs Headroom, summed from the cells (no extra Apex round-trip).
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
                hasHeadroom: g > 0
            };
        });
    }

    get columns() {
        return this.matrix ? this.matrix.families : [];
    }

    get rows() {
        if (!this.matrix) return [];
        const families = this.matrix.families;
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
        return order.map((k) => {
            const node = byNode.get(k);
            const cells = families.map((f) => {
                const c = node.cells.get(f.id);
                if (c) {
                    const amount =
                        c.arr != null && c.arr > 0
                            ? this.fmt(c.arr)
                            : c.expectedRevenue != null && c.expectedRevenue > 0
                            ? this.fmt(c.expectedRevenue)
                            : '—';
                    return {
                        key: f.id,
                        cssClass: STATE_CLASS[c.state] || 'cell c-na',
                        amount,
                        sub: STATE_LABEL[c.state] || ''
                    };
                }
                return { key: f.id, cssClass: 'cell c-na', amount: 'n/a', sub: '' };
            });
            return {
                key: k,
                label: node.label,
                officeUrl: node.officeAccountId ? '/' + node.officeAccountId : null,
                cells
            };
        });
    }

    async handleRecalc() {
        this.recalculating = true;
        try {
            const count = await recalcHeadroom({ planId: this.recordId });
            await refreshApex(this.wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Headroom recalculated',
                    message: `${count} white-space cell${count === 1 ? '' : 's'} updated`,
                    variant: 'success'
                })
            );
        } catch (e) {
            const message = e && e.body && e.body.message ? e.body.message : 'Unknown error';
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Recalculation failed', message, variant: 'error' })
            );
        } finally {
            this.recalculating = false;
        }
    }

    fmt(n) {
        if (n >= 1000000) return '£' + (n / 1000000).toFixed(2) + 'M';
        if (n >= 1000) return '£' + Math.round(n / 1000) + 'K';
        return '£' + n;
    }
}
