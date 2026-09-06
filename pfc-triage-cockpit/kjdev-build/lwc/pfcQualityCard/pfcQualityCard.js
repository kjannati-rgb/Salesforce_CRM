import { LightningElement, api, wire } from 'lwc';
import getCardData from '@salesforce/apex/PFCQualityCardController.getCardData';

const GAUGE_CIRCUMFERENCE = 141; // matches the mockup arc path length
// Provisional score bands — Clay scoring owner to confirm (brief open question 6)
const BAND_GOOD = 70;
const BAND_MID = 40;

export default class PfcQualityCard extends LightningElement {
    @api recordId;

    data;
    error;

    @wire(getCardData, { recordId: '$recordId' })
    wired({ data, error }) {
        this.data = data;
        this.error = error;
    }

    get isLeadMode() {
        return this.data?.mode === 'lead';
    }

    get isContactMode() {
        return this.data?.mode === 'contact';
    }

    get title() {
        return this.isContactMode ? 'Account Context' : 'Lead Quality';
    }

    // ---- gauge ----
    get hasScore() {
        return this.data?.fitScore !== null && this.data?.fitScore !== undefined;
    }

    get scorePending() {
        return this.isLeadMode && !this.hasScore;
    }

    get gaugeArcStyle() {
        if (!this.hasScore) {
            return 'stroke:#e5e5e5';
        }
        const score = Math.max(0, Math.min(100, this.data.fitScore));
        const offset = GAUGE_CIRCUMFERENCE * (1 - score / 100);
        const colour =
            score >= BAND_GOOD ? '#2e844a' : score >= BAND_MID ? '#dd7a01' : '#ba0517';
        return `stroke:${colour};stroke-dasharray:${GAUGE_CIRCUMFERENCE};stroke-dashoffset:${offset}`;
    }

    get scoreNumberClass() {
        if (!this.hasScore) {
            return 'num-value pending';
        }
        const score = this.data.fitScore;
        return (
            'num-value ' +
            (score >= BAND_GOOD ? 'good' : score >= BAND_MID ? 'mid' : 'poor')
        );
    }

    get scoreDisplay() {
        return this.hasScore ? String(this.data.fitScore) : '—';
    }

    // ---- badges ----
    get isCorporateDomain() {
        return this.data?.domainClass === 'corporate';
    }

    get isFreemailDomain() {
        return this.data?.domainClass === 'freemail';
    }

    get corporateBadgeLabel() {
        return `✓ Corporate domain · ${this.data?.domainName}`;
    }

    get freemailBadgeLabel() {
        return `⚠ Free-mail address · ${this.data?.domainName}`;
    }

    get showClayBadge() {
        return this.data?.clayRouted === true;
    }

    get hasSource() {
        return Boolean(this.data?.pfcSource);
    }

    get hasReasoning() {
        return Boolean(this.data?.scoreReasoning);
    }

    // ---- duplicates ----
    get hasDuplicates() {
        return (this.data?.duplicates || []).length > 0;
    }

    get duplicateCount() {
        return (this.data?.duplicates || []).length;
    }

    get duplicateHeadline() {
        const n = this.duplicateCount;
        return `${n} other completion${n === 1 ? '' : 's'} from this prospect in the last 90 days`;
    }

    get duplicateRows() {
        return (this.data?.duplicates || []).map((d) => ({
            ...d,
            url: '/' + d.recordId
        }));
    }

    // ---- firm context (contact mode) ----
    get firm() {
        return this.data?.firm;
    }

    // Contact-linked records can lack any account (private contact, or a record created
    // already-closed so the account stamp never ran) — never bind firm.* unguarded.
    get showFirmContext() {
        return this.isContactMode && Boolean(this.firm);
    }

    get contactWithoutAccount() {
        return this.isContactMode && !this.firm;
    }

    get hasFirmSubs() {
        return (this.firm?.activeSubs || 0) > 0;
    }

    get noFirmSubs() {
        return !this.hasFirmSubs;
    }

    get familiesLine() {
        const n = this.firm?.familyCount || 0;
        return `across ${n} product ${n === 1 ? 'family' : 'families'} (firm-wide)`;
    }

    get holdingsSummary() {
        return (this.firm?.families || [])
            .map((f) => `${f.count}× ${f.family}`)
            .join(' · ');
    }

    get firmBadgeLabel() {
        return `Firm: ${this.firm?.firmName}`;
    }

    get officeBadgeLabel() {
        return `Office: ${this.firm?.officeName}`;
    }

    get showEntitlementFlag() {
        return this.firm?.requestedBrandFamilyOverlap === true;
    }

    get entitlementText() {
        const f = this.firm;
        return (
            `Entitlement check: prospect requested ${f.requestedBrand} — the firm already holds ` +
            `subscriptions in ${f.requestedFamily}, the family ${f.requestedBrand} sits in. ` +
            `Verify whether this person is covered by an existing licence before selling. ` +
            `If covered → route to CSM as a seat/access request. If not → genuine expansion ` +
            `signal for the account owner.`
        );
    }

    get expansionText() {
        const f = this.firm;
        const brandBit = f?.requestedBrand ? ` in ${f.requestedBrand}` : '';
        return `No existing firm coverage${brandBit} found — treat as a genuine expansion signal for the account owner.`;
    }
}
