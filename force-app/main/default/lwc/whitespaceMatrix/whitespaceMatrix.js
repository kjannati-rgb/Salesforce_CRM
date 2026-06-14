import { LightningElement, api, wire } from 'lwc';
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

export default class WhitespaceMatrix extends LightningElement {
    @api recordId;
    matrix;
    error;

    @wire(getMatrix, { planId: '$recordId' })
    wiredMatrix({ data, error }) {
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
        const parts = [this.matrix.segment, this.matrix.tier, this.matrix.dealModel].filter((p) => p);
        return parts.join(' · ');
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
                byNode.set(c.nodeKey, { key: c.nodeKey, label: c.nodeLabel, cells: new Map() });
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
            return { key: k, label: node.label, cells };
        });
    }

    fmt(n) {
        if (n >= 1000000) return '£' + (n / 1000000).toFixed(2) + 'M';
        if (n >= 1000) return '£' + Math.round(n / 1000) + 'K';
        return '£' + n;
    }
}
