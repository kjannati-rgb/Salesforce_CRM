import { LightningElement, api, wire } from 'lwc';
import getTrend from '@salesforce/apex/AccountPlanController.getTrend';

export default class PlanTrend extends LightningElement {
    @api recordId;
    points;
    error;

    @wire(getTrend, { planId: '$recordId' })
    wiredTrend({ data, error }) {
        if (data) {
            this.points = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.points = undefined;
        }
    }

    get hasData() {
        return this.points && this.points.length > 0;
    }

    get bars() {
        if (!this.hasData) return [];
        const max = Math.max(...this.points.map((p) => p.totalArr || 0), 1);
        return this.points.map((p) => ({
            key: p.snapshotDate,
            label: this.fmtDate(p.snapshotDate),
            amount: this.fmt(p.totalArr || 0),
            barStyle: `height:${Math.max(3, Math.round(((p.totalArr || 0) / max) * 100))}%`
        }));
    }

    get deltaLabel() {
        if (!this.hasData || this.points.length < 2) return '';
        const d = (this.points[this.points.length - 1].totalArr || 0) - (this.points[0].totalArr || 0);
        const arrow = d < 0 ? '▼' : d > 0 ? '▲' : '■';
        return `${arrow} ${this.fmt(Math.abs(d))} ARR since first snapshot`;
    }

    get deltaClass() {
        if (!this.hasData || this.points.length < 2) return 'delta';
        const d = (this.points[this.points.length - 1].totalArr || 0) - (this.points[0].totalArr || 0);
        // Rising ARR = white space being converted to owned revenue = good.
        return d > 0 ? 'delta good' : d < 0 ? 'delta watch' : 'delta';
    }

    fmt(n) {
        if (n >= 1000000) return '£' + (n / 1000000).toFixed(2) + 'M';
        if (n >= 1000) return '£' + Math.round(n / 1000) + 'K';
        return '£' + (n || 0);
    }

    fmtDate(d) {
        if (!d) return '';
        return new Date(d).toLocaleDateString('en-GB', { month: 'short', day: 'numeric' });
    }
}
