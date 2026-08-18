import { LightningElement, api } from 'lwc';
import getMatch from '@salesforce/apex/SmartConvertController.getMatch';
import getOfficesForFirm from '@salesforce/apex/SmartConvertController.getOfficesForFirm';
import convertLead from '@salesforce/apex/SmartConvertController.convert';
import createAccountShell from '@salesforce/apex/SmartConvertController.createAccountShell';
import searchFirms from '@salesforce/apex/SmartConvertController.searchFirms';
import getOwnership from '@salesforce/apex/SmartConvertController.getOwnership';
import createFollowUpTask from '@salesforce/apex/SmartConvertController.createFollowUpTask';
import getBuyingCommittee from '@salesforce/apex/SmartConvertController.getBuyingCommittee';
import USER_ID from '@salesforce/user/Id';

const STEPS = ['Inbound', 'Match', 'Choose office', 'Confirm', 'Done'];

export default class SmartConvert extends LightningElement {
    // Load only once recordId actually arrives — in a quick-action/wrapper context it
    // propagates after mount, so a connectedCallback load would run with a null id.
    _recordId;
    _loaded = false;
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._loaded) {
            this._loaded = true;
            this.load();
        }
    }

    data;
    offices = [];
    step = 0;
    sel = 0;
    firmChosen = false;
    pendingFirmId;
    chosenFirmName;
    loading = true;
    converting = false;
    convertingStep = 0;
    convertResult;
    error;
    createOpp = false;         // OFF by default — reps opt in when the enquiry should open a deal
    selectedContactId = null;
    selectedCurrency;
    // manual override (search & pick a firm)
    searchOpen = false;
    searchTerm = '';
    searchResults = [];
    searching = false;
    manualMode = false;
    manualFirm;
    ownership;
    committee;
    followUpDueDays = '2';
    followUpAssignee = 'me';
    followUpType = 'Call';
    followUpComments = '';
    creatingTask = false;
    taskCreated = false;
    taskUrl;
    taskError;

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.data = await getMatch({ leadId: this.recordId });
            this.offices = this.data.offices || [];
            this.sel = this.recoIndex(this.offices);
            // pre-select the first firm so the ambiguous picker's Next is enabled
            if (this.data.ambiguous && this.data.firmOptions && this.data.firmOptions.length) {
                this.pendingFirmId = this.data.firmOptions[0].id;
            }
            // default the contact selection to the recommended match (else "create new")
            const rec = (this.data.contactOptions || []).find((o) => o.recommended);
            this.selectedContactId = rec ? rec.id : null;
            this.selectedCurrency = this.data.defaultCurrency;
            // Opportunity creation is opt-in: the toggle starts OFF and the rep switches it
            // on when this enquiry should open a deal (business decision 2026-08-14).
            this.createOpp = false;
            this.loadFirmContext();
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'Unable to match.';
        }
        this.loading = false;
    }

    async loadFirmContext(firmIdArg) {
        const fid = firmIdArg || this.effectiveFirmId;
        if (!fid) { this.ownership = undefined; this.committee = undefined; return; }
        try {
            this.ownership = await getOwnership({ firmId: fid, brand: (this.data && this.data.brand) || null });
        } catch (e) {
            this.ownership = undefined;
        }
        try {
            this.committee = await getBuyingCommittee({ firmId: fid });
        } catch (e) {
            this.committee = undefined;
        }
    }

    recoIndex(offs) {
        if (!offs || !offs.length) return 0;
        const i = offs.findIndex((o) => o.reco);
        return i < 0 ? 0 : i;
    }

    // ===== stepper =====
    get stepper() {
        return STEPS.map((s, i) => ({
            label: s,
            num: i < this.step ? '✓' : String(i + 1),
            cls: 'sc-st' + (i === this.step ? ' sc-active' : '') + (i < this.step ? ' sc-done' : ''),
            showBar: i < STEPS.length - 1
        }));
    }

    get isStep0() { return this.step === 0 && !this.disqualifyOpen; }
    get isStep1() { return this.step === 1 && !this.disqualifyOpen; }
    get isStep2() { return this.step === 2 && !this.disqualifyOpen; }
    get isStep3() { return this.step === 3 && !this.disqualifyOpen; }
    get isStep4() { return this.step === 4 && !this.disqualifyOpen; }

    // ---- lead quality + in-flow disqualify ----
    disqualifyOpen = false;
    disqualified = false;
    disqualifying = false;
    disqualifyReason;
    get hasConvertTarget() {
        return this.isNoMatch || this.firmNoOffice || (this.selectedOffice && this.selectedOffice.id);
    }
    get hasQuality() {
        const q = this.data && this.data.quality;
        return q && (q.grade || q.score != null || q.emailStatus);
    }
    get emailBad() { return this.data && this.data.quality && this.data.quality.emailBad; }
    // Grade/Score are key metrics — when a lead has none, flag the absence explicitly.
    get showNoScore() {
        if (!this.data) return false;
        const q = this.data.quality;
        return !q || (!q.grade && q.score == null);
    }
    get emailChipClass() {
        const q = this.data && this.data.quality;
        if (!q || !q.emailStatus) return 'sc-qchip';
        return 'sc-qchip ' + (q.emailValid ? 'sc-q-ok' : (q.emailBad ? 'sc-q-bad' : 'sc-q-warn'));
    }
    get showDisqualifyBtn() {
        return !this.disqualified && !this.isStep4 && !this.disqualifyOpen && this.hasConvertTarget;
    }
    // Footer controls: hidden on the Done screen (the lead is already converted — Back/Restart
    // make no sense there), but kept when the convert was BLOCKED so the rep can go Back and retry.
    get showControls() { return !this.disqualifyOpen && (this.step !== 4 || this.convertBlocked); }
    get envPill() { return (this.data && this.data.envLabel) || ''; }
    get convertingMsg() {
        const msgs = ['Running duplicate checks…', 'Placing under the right firm…', 'Linking the contact…', 'Creating the opportunity…', 'Finishing up…'];
        return msgs[Math.min(this.convertingStep, msgs.length - 1)];
    }
    get disqualifyReasonOptions() {
        return ['Existing customer', 'Existing Opportunity', 'Duplicate enquiry',
            'Invalid email / bounced', 'Not ICP', 'Not interested', 'Other'].map((v) => ({ label: v, value: v }));
    }
    get suggestedDisqualifyReason() {
        // An existing customer is usually an upsell/renewal, NOT a disqualify — only pre-suggest a
        // disqualify reason for the genuine duplicate case (an open deal already covers this brand).
        if (this.data && this.data.hasOpenBrandOpp) return 'Existing Opportunity';
        if (this.emailBad) return 'Invalid email / bounced';
        return null;
    }
    openDisqualify() {
        this.searchOpen = false;
        this.disqualifyReason = this.suggestedDisqualifyReason;
        this.disqualifyOpen = true;
    }
    cancelDisqualify() { this.disqualifyOpen = false; }
    handleDisqualifyReason(e) { this.disqualifyReason = e.detail.value; }
    async doDisqualify() {
        // disqualify = convert into the account/contact (existing or created) with NO opportunity,
        // and record the reason — preserves the single customer view.
        this.disqualifyOpen = false;
        this.disqualifying = true;
        await this.confirmConvert();
        this.disqualifying = false;
        this.disqualified = (this.convertResult && this.convertResult.success === true);
        this.step = 4;
    }

    get showFirmPicker() { return this.data && this.data.ambiguous && !this.firmChosen && !this.manualMode; }
    get firmNoOffice() {
        if (this.manualMode) return this.offices.length === 0;
        return this.data && this.data.firmNoOffice;
    }
    get showOfficePicker() { return !this.showFirmPicker && !this.isNoMatch && !this.firmNoOffice; }
    get showPlacement() { return !this.isNoMatch && !this.firmNoOffice; }
    get effectiveFirmId() {
        if (this.manualFirm) return this.manualFirm.id;
        return this.data && this.data.firm ? this.data.firm.id : null;
    }

    get scanItems() {
        const s = (this.data && this.data.scan) || [];
        return s.map((html, i) => ({ key: i, html, style: `animation-delay:${i * 0.14}s` }));
    }
    get confClass() { return 'sc-conf sc-' + ((this.data && this.data.conf) || 'none'); }

    get firmOptions() {
        return ((this.data && this.data.firmOptions) || []).map((f) => ({
            ...f,
            cls: 'sc-cand' + (f.id === this.pendingFirmId ? ' sc-sel' : ''),
            radioCls: 'sc-radio' + (f.id === this.pendingFirmId ? ' sc-on' : ''),
            ariaChecked: String(f.id === this.pendingFirmId)
        }));
    }

    get decoratedOffices() {
        const max = Math.max(1, ...this.offices.map((o) => o.opps || 0));
        return this.offices.map((o, i) => {
            const selected = i === this.sel;
            let badge = null;
            if (o.reco === 'reco') badge = { cls: 'sc-badge sc-reco', label: '★ Most opportunities' };
            else if (o.reco === 'loc') badge = { cls: 'sc-badge sc-loc', label: 'Address match · recommended' };
            else if (o.reco === 'here') badge = { cls: 'sc-badge sc-here', label: 'Contact already here' };
            return {
                ...o,
                index: i,
                selected,
                cls: 'sc-cand' + (o.dim ? ' sc-dim' : '') + (selected ? ' sc-sel' : ''),
                radioCls: 'sc-radio' + (selected ? ' sc-on' : ''),
                ariaChecked: String(selected),
                hasBadge: !!badge,
                badgeCls: badge ? badge.cls : '',
                badgeLabel: badge ? badge.label : '',
                barStyle: `width:${Math.round(((o.opps || 0) / max) * 100)}%`
            };
        });
    }

    get selectedOffice() {
        return this.offices[this.sel] || this.offices[this.recoIndex(this.offices)];
    }
    get selectedContactOption() {
        return ((this.data && this.data.contactOptions) || []).find((o) => o.id === this.selectedContactId);
    }
    get linkingExistingContact() {
        return !!this.selectedContactId && !!this.selectedContactOption;
    }
    // When linking an existing contact, convert into THEIR office (we don't move people across offices).
    get targetOffice() {
        if (this.linkingExistingContact && this.selectedContactOption.officeId) {
            const off = this.offices.find((o) => o.id === this.selectedContactOption.officeId);
            if (off) return off;
        }
        return this.selectedOffice;
    }
    get possibleMove() {
        return this.linkingExistingContact && this.targetOffice && this.data && this.data.recommendedOfficeId
            && this.targetOffice.id !== this.data.recommendedOfficeId;
    }
    get recommendedOfficeName() {
        const id = this.data && this.data.recommendedOfficeId;
        const off = id && this.offices.find((o) => o.id === id);
        return off ? off.nm : '';
    }
    get linkedContactName() {
        return this.selectedContactOption ? this.selectedContactOption.name : 'this contact';
    }

    get bannerCls() { return 'sc-banner sc-' + ((this.data && this.data.banner && this.data.banner.cls) || 'info'); }

    // confirm-screen variant
    get isNoMatch() {
        if (this.manualMode) return false;
        return this.data && !this.data.hasFirm && !this.data.ambiguous;
    }
    get isLinkExisting() { return this.data && this.data.contact && this.data.contact.result === 'found'; }
    get isNormalConfirm() { return !this.isNoMatch && !this.isLinkExisting; }
    get contactOk() { return this.data && this.data.contact && this.data.contact.result === 'none'; }
    get hasContactOptions() { return this.data && this.data.contactOptions && this.data.contactOptions.length > 0; }
    get hasOwnership() {
        return this.ownership && (this.ownership.firmOwner || this.ownership.hasTeam);
    }
    get ownershipTeamView() {
        return ((this.ownership && this.ownership.team) || []).map((tm) => ({
            key: `${tm.name}|${tm.role}`,
            label: `${tm.name} · ${tm.role}` + (tm.covers ? ' · covers this product' : ''),
            cls: 'sc-tmchip' + (tm.covers ? ' sc-tmchip-you' : (tm.isYou ? ' sc-tmchip-you' : ''))
        }));
    }
    get relevantCsm() {
        const o = this.ownership;
        return o && o.relevantName ? o : null;
    }
    // ----- buying committee -----
    get hasCommittee() { return this.committee && this.committee.count > 0; }
    get committeeSummary() {
        const c = this.committee;
        if (!c) return '';
        const offices = c.officeCount === 1 ? '1 office' : `${c.officeCount} offices`;
        return `${c.count} known contact${c.count === 1 ? '' : 's'} across ${offices}`;
    }
    get coverageView() {
        return ((this.committee && this.committee.coverage) || []).map((cv) => ({
            persona: cv.persona,
            label: cv.covered ? cv.persona : `${cv.persona} — gap`,
            cls: 'sc-cov' + (cv.covered ? ' sc-cov-on' : ' sc-cov-gap')
        }));
    }
    get committeeMembersView() {
        return ((this.committee && this.committee.members) || []).slice(0, 8).map((m) => {
            const meta = [m.title, m.office, m.lastActivity ? 'active ' + m.lastActivity : '']
                .filter(Boolean).join(' · ');
            return {
                id: m.id,
                name: m.name,
                url: m.url,
                meta,
                persona: m.persona,
                showPersona: !!m.persona,
                personaCls: 'sc-pchip' + (m.senior ? ' sc-pchip-snr' : '')
            };
        });
    }
    get committeeMore() {
        const c = this.committee;
        return c && c.count > 8 ? c.count - 8 : 0;
    }
    // ----- collapsible account-context bar (ownership + committee) -----
    contextOpen = false;
    get hasContext() { return this.hasOwnership || this.hasCommittee; }
    get contextSummary() {
        const parts = [];
        const csm = this.relevantCsm;
        if (csm) parts.push(`${csm.relevantName} · ${csm.relevantRole}`);
        else if (this.ownership && this.ownership.hasTeam) parts.push(`${this.ownership.team.length} team member${this.ownership.team.length === 1 ? '' : 's'}`);
        const c = this.committee;
        if (c && c.count) parts.push(`${c.count} contact${c.count === 1 ? '' : 's'}`);
        if (c && c.gaps) parts.push(`${c.gaps} committee gap${c.gaps === 1 ? '' : 's'}`);
        return parts.join(' · ');
    }
    get contextBarCls() { return 'sc-ctx-bar' + (this.contextOpen ? ' sc-open' : ''); }
    toggleContext() { this.contextOpen = !this.contextOpen; }
    get hasOpenOpps() { return this.data && this.data.openOpps && this.data.openOpps.length > 0; }
    get openOppWarnClass() { return 'sc-banner ' + ((this.data && this.data.hasOpenBrandOpp) ? 'sc-warn' : 'sc-info'); }
    get openOppHeadline() {
        const n = (this.data && this.data.openOpps) ? this.data.openOpps.length : 0;
        if (this.data && this.data.hasOpenBrandOpp) {
            return `This firm already has an open ${this.data.brand} opportunity — consider adding to it instead of creating a second. The "create opportunity" toggle is off by default.`;
        }
        return `This firm already has ${n} open opportunit${n === 1 ? 'y' : 'ies'} — check before creating a new one.`;
    }
    get openOppsView() {
        return ((this.data && this.data.openOpps) || []).map((o) => {
            const meta = [o.stage, o.type, o.amount, o.closeDate ? 'closes ' + o.closeDate : '', o.owner]
                .filter(Boolean).join(' · ');
            let renewal = '';
            if (o.renewalDate) {
                const kind = o.autoRenew ? 'Auto-renewal' : 'Renewal';
                renewal = `${kind} · budget renewal ${o.renewalDate}`;
            } else if (o.autoRenew) {
                renewal = 'Auto-renewal';
            } else if (o.isRenewal) {
                renewal = 'Renewal';
            }
            return {
                ...o,
                meta,
                renewal,
                tag: o.sameBrand ? `same brand (${this.data.brand})` : ''
            };
        });
    }
    get contactPickerOptions() {
        const opts = (this.data.contactOptions || []).map((o) => ({
            ...o,
            isReal: true,
            selected: o.id === this.selectedContactId,
            ariaChecked: String(o.id === this.selectedContactId),
            cls: 'sc-cand' + (o.id === this.selectedContactId ? ' sc-sel' : ''),
            radioCls: 'sc-radio' + (o.id === this.selectedContactId ? ' sc-on' : '')
        }));
        const createSel = !this.selectedContactId;
        opts.push({
            id: '_new', isReal: false, name: 'Create a new contact', title: 'not yet in Salesforce',
            office: '', lastActivity: '', tag: 'new', recommended: false, sameFirm: false,
            selected: createSel,
            ariaChecked: String(createSel),
            cls: 'sc-cand' + (createSel ? ' sc-sel' : ''),
            radioCls: 'sc-radio' + (createSel ? ' sc-on' : '')
        });
        return opts;
    }
    handleSelectContact(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedContactId = id && id !== '_new' ? id : null;
    }
    get contactBannerCls() { return 'sc-banner ' + (this.contactOk ? 'sc-ok' : 'sc-info'); }
    get contactIc() { return this.contactOk ? 'check' : 'link'; }
    get reasonDisq() { return this.disqualifying ? this.disqualifyReason : ''; }

    // ----- sales motion (existing client = upsell/renewal/cross-sell, not a disqualify) -----
    get oppMotion() { return (this.data && this.data.oppMotion) || 'New Business'; }
    get isExpansion() {
        const m = this.oppMotion;
        return m === 'Upsell' || m === 'Renewal' || m === 'Cross-sell';
    }
    get isRenewal() { return this.oppMotion === 'Renewal'; }
    get renewalDateText() {
        const d = this.data && this.data.renewalDate;
        if (!d) return '';
        const dt = new Date(d);
        return Number.isNaN(dt.getTime()) ? '' : dt.toLocaleDateString();
    }
    // The create-opp toggle label reflects what we're actually creating.
    get oppToggleLabel() {
        if (this.oppMotion === 'Renewal') return 'Also create the renewal opportunity';
        if (this.oppMotion === 'Upsell') return 'Also create the upsell opportunity';
        if (this.oppMotion === 'Cross-sell') return 'Also create the cross-sell opportunity';
        return 'Also create a new-business opportunity';
    }
    get placementFirmName() {
        if (this.manualFirm) return this.manualFirm.name;
        if (this.data && this.data.firm) return this.data.firm.name;
        return this.chosenFirmName || 'Selected Firm';
    }
    get firmInitial() {
        const n = this.placementFirmName;
        return n && n.length ? n.substring(0, 1).toUpperCase() : '?';
    }

    // done
    get convertBlocked() { return this.convertResult && this.convertResult.success === false; }
    get showDoneSuccess() { return !this.convertBlocked && !this.disqualified; }
    get isDoneDisqualified() { return this.disqualified; }
    get disqualifyDisabled() { return this.converting || !this.disqualifyReason; }
    get hasConvertIds() { return this.convertResult && this.convertResult.accountId; }
    get accountUrl() { return this.recordUrl('Account', this.convertResult && this.convertResult.accountId); }
    get contactUrl() { return this.recordUrl('Contact', this.convertResult && this.convertResult.contactId); }
    get oppUrl() { return this.recordUrl('Opportunity', this.convertResult && this.convertResult.opportunityId); }
    get hasOpp() { return this.convertResult && this.convertResult.opportunityId; }
    recordUrl(obj, id) { return id ? `/lightning/r/${obj}/${id}/view` : null; }
    get done() {
        const avoided = (this.convertResult && this.convertResult.duplicatesAvoidedThisWeek != null)
            ? String(this.convertResult.duplicatesAvoidedThisWeek) : '—';
        if (this.isNoMatch) return { t: 'New customer — created cleanly', s: 'A new firm with its first office, checked for duplicates at both the account and contact level. No stray records.', k: '+1', cap: 'new account created the right way' };
        if (this.firmNoOffice) return { t: 'Office added under the firm', s: 'A new office under the existing firm, with the lead converted into it. The firm\'s totals are intact and there\'s no duplicate firm.', k: '+1', cap: 'office added without a duplicate firm' };
        if (this.isLinkExisting) return { t: 'Linked — no duplicate person', s: 'The enquiry was attached to the existing contact: activity logged, blank fields filled in, and their verified details left untouched.', k: avoided, cap: 'duplicates avoided this week' };
        return { t: 'Converted. No duplicate.', s: 'The contact joined the right existing office instead of creating another account — and we checked for an existing person, not just the company.', k: avoided, cap: 'duplicates avoided this week' };
    }
    get doneEyebrow() { return (this.isNoMatch || this.firmNoOffice) ? 'Created' : this.isLinkExisting ? 'Linked' : 'Converted'; }

    // ----- post-convert next action (follow-up task) -----
    get nextStepText() {
        // Ownership isn't territory at Centellic — guidance keys off the account TEAM member whose
        // role covers the lead's product (Law.com CSM / PI CSM / E&I CSM), when one exists.
        const csm = this.relevantCsm;
        const who = csm ? `${csm.relevantName} (${csm.relevantRole})` : null;
        const m = this.oppMotion;
        if (m === 'Renewal' || m === 'Upsell') {
            return who
                ? `Confirm timing with ${who} before reaching out.`
                : 'Confirm timing with the CSM covering this account, then reach out.';
        }
        if (m === 'Cross-sell') {
            const fam = this.data && this.data.brandFamily;
            const base = fam
                ? `Position the adjacent ${fam} title and set up an intro call.`
                : 'Position the adjacent product and set up an intro call.';
            return who ? `${base.slice(0, -1)} — loop in ${who}.` : base;
        }
        const brand = this.data && this.data.brand;
        const base = brand
            ? `Qualify the ${brand} enquiry and book a discovery call.`
            : 'Qualify the enquiry and book a discovery call.';
        return who ? `${base} ${who} covers this firm.` : base;
    }
    get followUpSubject() {
        const firm = this.placementFirmName || (this.data && this.data.inbound && this.data.inbound.company) || '';
        const who = this.data && this.data.inbound ? this.data.inbound.name : '';
        const brand = this.data && this.data.brand ? this.data.brand + ' ' : '';
        return `Follow up — ${brand}${this.oppMotion}: ${firm}${who ? ' (' + who + ')' : ''}`;
    }
    get dueOptions() {
        return [
            { label: 'Tomorrow', value: '1' },
            { label: 'In 2 days', value: '2' },
            { label: 'In 5 days', value: '5' },
            { label: 'Next week', value: '7' }
        ];
    }
    get assigneeOptions() {
        const opts = [{ label: 'Me', value: 'me' }];
        const seen = new Set([USER_ID]);
        const o = this.ownership;
        // Account team first (the real coverage signal here), covering CSM at the top
        const team = (o && o.team) || [];
        const ordered = [...team.filter((tm) => tm.covers), ...team.filter((tm) => !tm.covers)];
        ordered.forEach((tm) => {
            if (tm.userId && !seen.has(tm.userId)) {
                seen.add(tm.userId);
                opts.push({ label: `${tm.name} (${tm.role})`, value: tm.userId });
            }
        });
        if (o && o.firmOwnerId && !seen.has(o.firmOwnerId) && o.firmOwner) {
            opts.push({ label: `${o.firmOwner} (account owner)`, value: o.firmOwnerId });
        }
        return opts;
    }
    get showAssignee() { return this.assigneeOptions.length > 1; }
    get taskTypeOptions() {
        // Curated SDR subset of the org's Task Type picklist (the full list is CSM/automation-heavy).
        return ['Call', 'Email', 'Meeting', 'Product Demo', 'Product Trial', 'Connect on LinkedIn', 'Other']
            .map((v) => ({ label: v, value: v }));
    }
    handleTypeChange(e) { this.followUpType = e.detail.value; }
    handleCommentsChange(e) { this.followUpComments = e.detail.value; }
    get showTaskForm() { return !this.taskCreated; }
    handleDueChange(e) { this.followUpDueDays = e.detail.value; }
    handleAssigneeChange(e) { this.followUpAssignee = e.detail.value; }
    async createTask() {
        if (this.creatingTask || this.taskCreated) return;
        this.creatingTask = true;
        this.taskError = undefined;
        try {
            const assignTo = this.followUpAssignee === 'me' ? null : this.followUpAssignee;
            const comments = (this.followUpComments || '').trim();
            const res = await createFollowUpTask({
                opportunityId: (this.convertResult && this.convertResult.opportunityId) || null,
                contactId: (this.convertResult && this.convertResult.contactId) || null,
                accountId: (this.convertResult && this.convertResult.accountId) || null,
                subject: this.followUpSubject,
                dueInDays: parseInt(this.followUpDueDays, 10),
                assignToUserId: assignTo,
                taskType: this.followUpType,
                note: comments || null
            });
            if (res && res.taskId) {
                this.taskCreated = true;
                this.taskUrl = res.url;
            } else {
                this.taskError = (res && res.message) || 'Could not create the task.';
            }
        } catch (e) {
            this.taskError = (e && e.body && e.body.message) || (e && e.message) || 'Could not create the task.';
        }
        this.creatingTask = false;
    }

    // ===== interactions =====
    handleSelectOffice(e) { this.sel = Number(e.currentTarget.dataset.i); }
    handleSelectFirm(e) { this.pendingFirmId = e.currentTarget.dataset.id; }
    // Keyboard activation for the card pickers: Enter/Space behave like a click.
    handleCardKey(e) {
        if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            e.currentTarget.click();
        }
    }

    // ---- manual override: search & pick a firm ----
    openSearch() { this.searchOpen = true; this.searchResults = []; this.searchTerm = ''; }
    resetToRecommendation() {
        this.manualMode = false;
        this.manualFirm = undefined;
        this.chosenFirmName = undefined;
        this.firmChosen = false;
        this.searchOpen = false;
        this.loadFirmContext();
        this.offices = (this.data && this.data.offices) || [];
        this.sel = this.recoIndex(this.offices);
    }
    handleSearchInput(e) { this.searchTerm = e.target.value; }
    async runSearch() {
        if (!this.searchTerm || this.searchTerm.trim().length < 2) return;
        this.searching = true;
        this.error = undefined;
        try {
            this.searchResults = await searchFirms({ term: this.searchTerm });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Search failed.';
        }
        this.searching = false;
    }
    async pickManualFirm(e) {
        // Rows are keyed on officeId||id — a firm row and its office rows share the same firm id.
        const key = e.currentTarget.dataset.key;
        const f = (this.searchResults || []).find((x) => (x.officeId || x.id) === key);
        if (!f) return;
        const firmId = f.id;
        this.manualFirm = { id: firmId, name: f.firmName || f.name };
        this.chosenFirmName = this.manualFirm.name;
        try {
            this.offices = await getOfficesForFirm({ leadId: this.recordId, firmId });
            // An office hit pre-selects that office; a firm hit takes the recommendation.
            const oIdx = f.officeId ? this.offices.findIndex((o) => o.id === f.officeId) : -1;
            this.sel = oIdx >= 0 ? oIdx : this.recoIndex(this.offices);
        } catch (err) {
            this.error = 'Unable to load offices for the selected firm.';
        }
        this.manualMode = true;
        this.firmChosen = true;
        this.searchOpen = false;
        this.loadFirmContext();
    }
    get searchResultsView() {
        return (this.searchResults || []).map((f) => ({
            ...f,
            key: f.officeId || f.id,
            cls: 'sc-cand',
            radioCls: 'sc-radio'
        }));
    }

    get nextLabel() {
        if (this.step === 2) {
            if (this.showFirmPicker) return 'Choose company →';
            if (this.isNoMatch || this.firmNoOffice) return 'Continue →';
            if (this.isLinkExisting) return 'Review match →';
            return 'Convert →';
        }
        if (this.step === 3) {
            if (this.isLinkExisting) return 'Confirm & link →';
            if (this.isNoMatch) return 'Create →';
            if (this.firmNoOffice) return 'Create Office & convert →';
            return 'Confirm & convert →';
        }
        if (this.step === 4) return 'Restart ↺';
        return 'Next →';
    }
    get backDisabled() { return this.step === 0 || this.converting; }
    get nextDisabled() {
        return this.converting
            || (this.step === 2 && this.searchOpen)   // only blocks Next while the search overlay is open
            || (this.showFirmPicker && !this.pendingFirmId)
            || (this.step === 3 && this.isNoMatch && !this.createReason);   // require a create reason
    }

    async next() {
        // ambiguous: choose firm, then load its offices
        if (this.step === 2 && this.showFirmPicker) {
            const picked = (this.data.firmOptions || []).find((f) => f.id === this.pendingFirmId);
            this.chosenFirmName = picked ? picked.name : '';
            try {
                this.offices = await getOfficesForFirm({ leadId: this.recordId, firmId: this.pendingFirmId });
                this.sel = this.recoIndex(this.offices);
            } catch (e) {
                this.error = (e && e.body && e.body.message) || 'Unable to load offices.';
            }
            this.firmChosen = true;
            this.loadFirmContext(this.pendingFirmId);
            return;
        }
        // confirm -> convert
        if (this.step === 3) {
            await this.confirmConvert();
            this.step = 4;
            return;
        }
        if (this.step === 4) { this.restart(); return; }
        this.step = Math.min(STEPS.length - 1, this.step + 1);
    }

    back() {
        // If the search overlay is open, Back closes it first (stay on the office step).
        if (this.searchOpen) { this.searchOpen = false; return; }
        if (this.step === 2 && this.data.ambiguous && this.firmChosen) {
            this.firmChosen = false;
            this.offices = [];
            return;
        }
        this.step = Math.max(0, this.step - 1);
    }

    handleOppToggle(e) { this.createOpp = e.target.checked; }

    // ---- express path (high-confidence -> one click) ----
    createReason;
    get expressEligible() {
        return this.data && this.data.tier === 'ONECLICK' && !this.data.conflict
            && this.data.recommendedOfficeId && !this.data.ambiguous
            && !this.isNoMatch && !this.firmNoOffice && !this.manualMode && !this.data.hasOpenBrandOpp;
    }
    get expressExtra() {
        let s = '';
        if (this.isExpansion) s += ' · ' + this.oppMotion.toLowerCase();
        if (this.createOpp) s += ' · opportunity in ' + (this.selectedCurrency || this.data.defaultCurrency || '');
        return s;
    }
    async expressConvert() {
        await this.confirmConvert();
        this.step = 4;
    }

    // ---- create reason (required when a new firm is created) ----
    handleCreateReason(e) { this.createReason = e.detail.value; }
    get createReasonOptions() {
        return [
            { label: 'No existing firm matched', value: 'No existing firm matched' },
            { label: 'Existing firm not found in search', value: 'Existing firm not found in search' },
            { label: 'Genuinely new company', value: 'Genuinely new company' },
            { label: 'Other', value: 'Other' }
        ];
    }
    handleCurrencyChange(e) { this.selectedCurrency = e.detail.value; }
    get hasCurrencies() { return this.data && this.data.currencies && this.data.currencies.length > 1; }
    get showCurrency() { return this.createOpp && this.hasCurrencies; }
    get currencyOptions() { return ((this.data && this.data.currencies) || []).map((c) => ({ label: c, value: c })); }

    async confirmConvert() {
        this.converting = true;
        this.convertingStep = 0;
        const timer = setInterval(() => { this.convertingStep += 1; }, 850);
        let shellCreated = false;
        try {
            const tier = (this.data && this.data.tier) || null;
            // disqualify = convert for the SCV but with NO opportunity + a reason
            const makeOpp = this.disqualifying ? false : this.createOpp;
            const dqReason = this.disqualifying ? this.disqualifyReason : null;
            const cur = makeOpp ? this.selectedCurrency : null;
            const manual = this.manualMode === true;
            if (this.isNoMatch || this.firmNoOffice) {
                // Two transactions on purpose: the account inserts (managed dedup/enrichment
                // triggers + Account flows) must not share a governor budget with the convert
                // and the Opportunity master flow — a combined run blew the SOQL limit in prod.
                const shell = await createAccountShell({
                    leadId: this.recordId,
                    firmId: this.isNoMatch ? null : this.effectiveFirmId
                });
                if (!shell || !shell.success) {
                    this.convertResult = shell || { success: false, message: 'Create blocked.' };
                } else {
                    shellCreated = true;
                    this.convertResult = await convertLead({
                        leadId: this.recordId,
                        officeId: shell.accountId,
                        contactId: null,
                        createOpportunity: makeOpp,
                        matchConfidence: tier,
                        newAccountCreated: true,
                        currencyIsoCode: cur,
                        recommendedOfficeId: null,
                        manualSearchUsed: manual,
                        createReason: this.isNoMatch ? this.createReason : null,
                        disqualifyReason: dqReason
                    });
                    if (this.convertResult && this.convertResult.success === false) {
                        this.convertResult = {
                            ...this.convertResult,
                            message: (this.convertResult.message || 'Convert failed.') +
                                ' The new account was still created — fix the named issue, then Restart: the lead will match it (no duplicate will be made).'
                        };
                    }
                }
            } else if (this.selectedOffice && this.selectedOffice.id) {
                // resolved firm (including after the ambiguous picker) -> convert into the chosen office
                this.convertResult = await convertLead({
                    leadId: this.recordId,
                    officeId: (this.targetOffice && this.targetOffice.id) || this.selectedOffice.id,
                    contactId: this.selectedContactId || null,
                    createOpportunity: makeOpp,
                    matchConfidence: tier,
                    newAccountCreated: false,
                    currencyIsoCode: cur,
                    // When we land an existing contact in their own office (a "possible move"), that's
                    // by design, not a rep overriding the matcher — baseline the override flag to the
                    // office we actually converted into so the "matcher was wrong" signal stays clean.
                    recommendedOfficeId: this.linkingExistingContact
                        ? ((this.targetOffice && this.targetOffice.id) || (this.data && this.data.recommendedOfficeId) || null)
                        : ((this.data && this.data.recommendedOfficeId) || null),
                    manualSearchUsed: manual,
                    createReason: null,
                    disqualifyReason: dqReason
                });
            }
        } catch (e) {
            this.convertResult = {
                success: false,
                message: ((e && e.body && e.body.message) || 'Convert failed.') +
                    (shellCreated
                        ? ' The new account was still created — fix the named issue, then Restart: the lead will match it (no duplicate will be made).'
                        : '')
            };
        }
        clearInterval(timer);
        this.converting = false;
    }

    restart() {
        this.step = 0;
        this.firmChosen = false;
        this.pendingFirmId = undefined;
        this.convertResult = undefined;
        this.manualMode = false;
        this.manualFirm = undefined;
        this.chosenFirmName = undefined;
        this.createReason = undefined;
        this.searchOpen = false;
        this.load();
    }
}
