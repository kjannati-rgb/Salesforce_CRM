import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventsWithSpeakers from '@salesforce/apex/EventSpeakerCockpitController.getEventsWithSpeakers';
import getRoster from '@salesforce/apex/EventSpeakerCockpitController.getRoster';
import updateStatuses from '@salesforce/apex/EventSpeakerCockpitController.updateStatuses';
import bulkToggleField from '@salesforce/apex/EventSpeakerCockpitController.bulkToggleField';

// Funnel order for the kanban columns. If Speaker_Status__c picklist values
// change, update this list to match - kept explicit rather than derived from
// the live picklist so column order is a deliberate product decision, not
// whatever order admin happened to save values in.
const STATUS_COLUMNS = ['Lead', 'No Response', 'Pending', 'Confirmed', 'Decline', 'Cancelled'];

// The readiness/checklist fields shown as toggle chips on each card. This is
// the direct answer to the adoption problem: one click per chip instead of
// opening the record and editing six separate picklists.
const READINESS_FIELDS = [
    { field: 'receivedBio', apiName: 'Received_Bio__c', label: 'Bio' },
    { field: 'receivedPhoto', apiName: 'Received_Photo__c', label: 'Photo' },
    { field: 'sentCalendarInvite', apiName: 'Sent_Calendar_Invite__c', label: 'Cal. Invite' },
    { field: 'sentPreConferenceBriefing', apiName: 'Sent_Pre_Conference_Briefing__c', label: 'Briefing' },
    { field: 'sentThankYou', apiName: 'Sent_Thank_You_Email__c', label: 'Thank You' }
];

// v1 simplification: cycles blank -> Yes -> No -> blank. Received_Bio__c and
// Received_Photo__c also support a "Requested" value in the org today - fast
// follow if the events team wants that third state surfaced as a chip stop
// rather than folded into "blank".
const TOGGLE_CYCLE = ['', 'Yes', 'No'];

// Cards rendered per column before a "show more" click. Apex already returns
// the full roster in one call (cheap even at hundreds of rows) - this caps
// how much of it hits the DOM at once, since that's the actual bottleneck at
// scale, not the server round-trip.
const PAGE_SIZE = 30;

// Semantic color per status - drives the column dot, card accent border, and
// avatar fill. Kept in one map so the whole board reads as one color system
// instead of each element picking its own shade.
const STATUS_STYLE = {
    Lead: { accent: '#706e6b', bg: '#f3f2f2', text: '#3e3e3c' },
    'No Response': { accent: '#706e6b', bg: '#f3f2f2', text: '#3e3e3c' },
    Pending: { accent: '#b98200', bg: '#fef2dd', text: '#b98200' },
    Confirmed: { accent: '#04844b', bg: '#e3f8ee', text: '#04844b' },
    Decline: { accent: '#ba0517', bg: '#fde9e9', text: '#ba0517' },
    Cancelled: { accent: '#ba0517', bg: '#fde9e9', text: '#ba0517' }
};

export default class EventSpeakerRosterBoard extends NavigationMixin(LightningElement) {
    @track events = [];
    @track roster = [];
    selectedEventId;
    isLoading = false;
    errorMessage;
    searchTerm = '';
    missingFilter = '';
    visibleCounts = {};
    selectedIds = new Set();
    bulkFieldApiName = READINESS_FIELDS[0].apiName;

    connectedCallback() {
        this.loadEvents();
    }

    async loadEvents() {
        this.isLoading = true;
        try {
            await this.refreshEvents();
            if (!this.selectedEventId && this.events.length > 0) {
                this.selectedEventId = this.events[0].campaignId;
                await this.loadRoster();
            }
        } catch (e) {
            this.handleError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // Re-fetches just the event summary tiles (Total/Confirmed/etc counts)
    // without the isLoading spinner - used after a status move so the stat
    // bar catches up quietly instead of flashing a full-board spinner over
    // a card that already moved optimistically.
    async refreshEvents() {
        const data = await getEventsWithSpeakers();
        this.events = [...data].sort((a, b) => {
            const aTime = a.startDate ? new Date(a.startDate).getTime() : 0;
            const bTime = b.startDate ? new Date(b.startDate).getTime() : 0;
            return bTime - aTime;
        });
    }

    async loadRoster() {
        this.selectedIds = new Set();
        this.visibleCounts = {};
        if (!this.selectedEventId) {
            this.roster = [];
            return;
        }
        this.isLoading = true;
        try {
            this.roster = await getRoster({ campaignId: this.selectedEventId });
        } catch (e) {
            this.handleError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get eventOptions() {
        return this.events.map((e) => ({
            label: `${e.campaignName}${e.startDate ? ' \u2014 ' + e.startDate : ''} (${e.totalSpeakers})`,
            value: e.campaignId
        }));
    }

    get selectedEventSummary() {
        return this.events.find((e) => e.campaignId === this.selectedEventId);
    }

    get statusOptions() {
        return STATUS_COLUMNS.map((s) => ({ label: s, value: s }));
    }

    get bulkFieldOptions() {
        return READINESS_FIELDS.map((rf) => ({ label: rf.label, value: rf.apiName }));
    }

    get missingFilterOptions() {
        return [
            { label: 'All speakers', value: '' },
            { label: 'Missing any item', value: 'any' },
            ...READINESS_FIELDS.map((rf) => ({ label: `Missing ${rf.label}`, value: rf.apiName }))
        ];
    }

    get hasSelection() {
        return this.selectedIds.size > 0;
    }

    get selectedCount() {
        return this.selectedIds.size;
    }

    // Filtered against the full roster (already loaded, cheap array ops even
    // at hundreds of rows) so search and the missing-item filter both work
    // across everyone, not just what's currently paged into view.
    get filteredRoster() {
        let rows = this.roster;

        const term = (this.searchTerm || '').trim().toLowerCase();
        if (term) {
            rows = rows.filter((r) => {
                const haystack = `${r.speakerName || ''} ${r.jobTitle || ''} ${r.accountName || ''}`.toLowerCase();
                return haystack.includes(term);
            });
        }

        if (this.missingFilter === 'any') {
            rows = rows.filter((r) => READINESS_FIELDS.some((rf) => r[rf.field] !== 'Yes'));
        } else if (this.missingFilter) {
            const fieldKey = READINESS_FIELDS.find((rf) => rf.apiName === this.missingFilter)?.field;
            if (fieldKey) {
                rows = rows.filter((r) => r[fieldKey] !== 'Yes');
            }
        }

        return rows;
    }

    get columns() {
        const filtered = this.filteredRoster;
        return STATUS_COLUMNS.map((status) => {
            const allRows = filtered.filter((r) => r.status === status);
            const visibleCount = this.visibleCounts[status] || PAGE_SIZE;
            // Only decorate (compute chips, initials, card style) for the
            // slice actually rendered - this is what keeps a 300-speaker
            // column from building 300 fully wired-up cards on every
            // keystroke or toggle.
            const rows = allRows.slice(0, visibleCount).map((r) => this.decorateRow(r));
            const style = STATUS_STYLE[status] || STATUS_STYLE.Lead;
            return {
                status,
                count: allRows.length,
                rows,
                dotStyle: `background-color:${style.accent}`,
                hasMore: allRows.length > visibleCount,
                remaining: allRows.length - visibleCount
            };
        });
    }

    decorateRow(row) {
        const chips = READINESS_FIELDS.map((rf) => {
            const value = row[rf.field] || '';
            const isDone = value === 'Yes';
            const isNo = value === 'No';
            return {
                key: row.recordId + '-' + rf.apiName,
                label: rf.label,
                apiName: rf.apiName,
                recordId: row.recordId,
                value,
                iconName: isDone ? 'utility:check' : isNo ? 'utility:close' : null,
                chipClass: 'chip' + (isDone ? ' chip_done' : isNo ? ' chip_no' : '')
            };
        });
        const style = STATUS_STYLE[row.status] || STATUS_STYLE.Lead;
        return {
            ...row,
            chips,
            statusOptions: this.statusOptions,
            initials: this.getInitials(row.speakerName),
            cardStyle: `--accent-color:${style.accent};--accent-bg:${style.bg};--accent-text:${style.text}`,
            isSelected: this.selectedIds.has(row.recordId)
        };
    }

    getInitials(name) {
        if (!name) {
            return '?';
        }
        const parts = name.trim().split(/\s+/);
        const first = parts[0] ? parts[0][0] : '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
        return (first + last).toUpperCase();
    }

    navigateToContact(event) {
        event.preventDefault();
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactid;
        if (!contactId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contactId,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }

    navigateToRecord(event) {
        event.preventDefault();
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordid;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Event_Speaker_Management__c',
                actionName: 'view'
            }
        });
    }

    handleEventChange(event) {
        this.selectedEventId = event.detail.value;
        this.loadRoster();
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail.value;
        this.visibleCounts = {};
    }

    handleMissingFilterChange(event) {
        this.missingFilter = event.detail.value;
        this.visibleCounts = {};
    }

    handleShowMore(event) {
        const status = event.currentTarget.dataset.status;
        const current = this.visibleCounts[status] || PAGE_SIZE;
        this.visibleCounts = { ...this.visibleCounts, [status]: current + PAGE_SIZE };
    }

    handleSelectCard(event) {
        const recordId = event.currentTarget.dataset.recordid;
        const next = new Set(this.selectedIds);
        if (event.detail.checked) {
            next.add(recordId);
        } else {
            next.delete(recordId);
        }
        this.selectedIds = next;
    }

    handleClearSelection() {
        this.selectedIds = new Set();
    }

    handleBulkFieldChange(event) {
        this.bulkFieldApiName = event.detail.value;
    }

    handleBulkMarkDone() {
        this.applyBulkField('Yes');
    }

    handleBulkClear() {
        this.applyBulkField('');
    }

    async applyBulkField(newValue) {
        if (this.selectedIds.size === 0) {
            return;
        }
        const ids = [...this.selectedIds];
        const fieldKey = READINESS_FIELDS.find((rf) => rf.apiName === this.bulkFieldApiName)?.field;
        const previousRoster = this.roster;
        if (fieldKey) {
            this.roster = this.roster.map((r) => (ids.includes(r.recordId) ? { ...r, [fieldKey]: newValue } : r));
        }
        try {
            await bulkToggleField({ recordIds: ids, fieldApiName: this.bulkFieldApiName, newValue });
            this.showToast('Success', `Updated ${ids.length} record${ids.length === 1 ? '' : 's'}.`, 'success');
        } catch (e) {
            this.roster = previousRoster;
            this.handleError(e);
        }
    }

    async handleBulkStatusMove(event) {
        const newStatus = event.detail.value;
        if (!newStatus || this.selectedIds.size === 0) {
            return;
        }
        const ids = [...this.selectedIds];
        const previousRoster = this.roster;
        this.roster = this.roster.map((r) => (ids.includes(r.recordId) ? { ...r, status: newStatus } : r));
        try {
            await updateStatuses({ updates: ids.map((recordId) => ({ recordId, newStatus })) });
            this.showToast('Success', `Moved ${ids.length} speaker${ids.length === 1 ? '' : 's'} to ${newStatus}.`, 'success');
            this.selectedIds = new Set();
            await this.refreshEvents();
        } catch (e) {
            this.roster = previousRoster;
            this.handleError(e);
        }
    }

    async handleStatusMove(event) {
        const recordId = event.currentTarget.dataset.id;
        const newStatus = event.detail.value;
        const previousRoster = this.roster;
        this.roster = this.roster.map((r) => (r.recordId === recordId ? { ...r, status: newStatus } : r));
        try {
            await updateStatuses({ updates: [{ recordId, newStatus }] });
            this.showToast('Success', 'Speaker status updated.', 'success');
            await this.refreshEvents();
        } catch (e) {
            this.roster = previousRoster;
            this.handleError(e);
        }
    }

    async handleChipClick(event) {
        const { apiname: apiName, recordid: recordId, value } = event.currentTarget.dataset;
        const currentIndex = TOGGLE_CYCLE.indexOf(value);
        const nextValue = TOGGLE_CYCLE[(currentIndex + 1) % TOGGLE_CYCLE.length];
        const fieldKey = READINESS_FIELDS.find((rf) => rf.apiName === apiName)?.field;

        // Optimistic update: flip the chip immediately instead of waiting on
        // the round-trip, so it reads as an instant toggle. Roll back to the
        // pre-click roster only if the save actually fails.
        const previousRoster = this.roster;
        if (fieldKey) {
            this.roster = this.roster.map((r) =>
                r.recordId === recordId ? { ...r, [fieldKey]: nextValue } : r
            );
        }

        try {
            await bulkToggleField({ recordIds: [recordId], fieldApiName: apiName, newValue: nextValue });
        } catch (e) {
            this.roster = previousRoster;
            this.handleError(e);
        }
    }

    handleError(e) {
        const message = (e && e.body && e.body.message) ? e.body.message : 'Something went wrong.';
        this.errorMessage = message;
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
