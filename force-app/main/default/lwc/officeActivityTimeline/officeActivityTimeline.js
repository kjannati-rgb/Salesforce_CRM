import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOfficeActivities from '@salesforce/apex/OfficeActivityTimelineController.getOfficeActivities';

const ICONS = {
    Email: 'utility:email',
    Call: 'utility:call',
    Task: 'utility:task',
    Event: 'utility:event'
};

const TYPE_FILTERS = [
    { key: 'All', label: 'All' },
    { key: 'Email', label: 'Emails' },
    { key: 'Call', label: 'Calls' },
    { key: 'Task', label: 'Tasks' },
    { key: 'Event', label: 'Meetings' }
];

const HISTORY_BUCKETS = [
    ['today', 'Today'],
    ['yesterday', 'Yesterday'],
    ['week', 'Earlier this week'],
    ['month', 'This month'],
    ['older', 'Older']
];

const DAY = 86400000;

export default class OfficeActivityTimeline extends NavigationMixin(LightningElement) {
    @api recordId;
    @api monthsBack = 36;
    @api maxRecords = 1000;

    activities = [];
    totals;
    options; // full filter-option lists (offices/owners/teams/legalEntities) from the unfiltered load
    firmTotal = 0; // the firm's overall activity count, captured on the unfiltered load
    error;
    isLoading = true;
    isRefreshing = false;

    selectedId;
    activeType = 'All'; // client-side view filter (the others are applied server-side)
    officeFilter = 'All'; // holds an office Id
    ownerFilter = 'All'; // holds an owner (User) Id
    teamFilter = 'All';
    legalEntityFilter = 'All';
    searchKey = '';

    _searchTimer;

    // Load imperatively on mount. A @wire on getOfficeActivities left the timeline blank on a
    // record-page tab until the user pressed Refresh; connectedCallback fires once recordId and
    // the design attributes are set, so the data is present on first paint.
    connectedCallback() {
        this.loadActivities();
    }

    // The structured filters are sent to the server so they reach activity beyond the row cap; only
    // the type tab is applied client-side. The server returns the full filter-option lists (and the
    // firm-level total) on the unfiltered load, which we cache so dropdowns stay complete.
    async loadActivities() {
        if (!this.recordId) {
            return;
        }
        try {
            const data = await getOfficeActivities({
                accountId: this.recordId,
                monthsBack: this.monthsBack,
                maxRecords: this.maxRecords,
                officeId: this.officeFilter === 'All' ? null : this.officeFilter,
                ownerId: this.ownerFilter === 'All' ? null : this.ownerFilter,
                team: this.teamFilter === 'All' ? null : this.teamFilter,
                legalEntity: this.legalEntityFilter === 'All' ? null : this.legalEntityFilter,
                searchTerm: this.searchKey.trim() ? this.searchKey.trim() : null
            });
            this.activities = (data && data.activities) || [];
            this.totals = data || null;
            if (data && data.filterOptions) {
                this.options = data.filterOptions;
                this.firmTotal = data.totalAll;
            }
            this.error = undefined;
            const ids = new Set(this.activities.map((a) => a.id));
            if (!this.selectedId || !ids.has(this.selectedId)) {
                this.selectedId = this.activities.length ? this.activities[0].id : undefined;
            }
        } catch (e) {
            this.error = this.reduceError(e);
            this.activities = [];
            this.totals = null;
        } finally {
            this.isLoading = false;
        }
    }

    reload() {
        return this.loadActivities();
    }

    // ---- Derived data ---------------------------------------------------

    // Only the type tab is applied here; office/owner/team/legal/search were applied server-side.
    get filteredActivities() {
        if (this.activeType === 'All') {
            return this.activities;
        }
        return this.activities.filter((a) => a.type === this.activeType);
    }

    get groups() {
        const now = Date.now();
        const ref = new Date();
        const startOfToday = new Date(ref.getFullYear(), ref.getMonth(), ref.getDate()).getTime();

        const b = {
            overdue: [],
            upcoming: [],
            today: [],
            yesterday: [],
            week: [],
            month: [],
            older: []
        };

        this.filteredActivities.forEach((a) => {
            const decorated = this.decorate(a);
            const tms = a.activityDateTime ? new Date(a.activityDateTime).getTime() : null;

            if (a.objectApiName === 'Task' && a.isOpen) {
                if (tms !== null && tms < startOfToday) {
                    // Overdue: flag the status red to match the Overdue header.
                    decorated.statusClass = 'row-status row-status_overdue';
                    b.overdue.push(decorated);
                } else {
                    b.upcoming.push(decorated);
                }
            } else if (a.objectApiName === 'Event' && tms !== null && tms > now) {
                b.upcoming.push(decorated);
            } else if (tms !== null && tms >= startOfToday) {
                b.today.push(decorated);
            } else if (tms !== null && tms >= startOfToday - DAY) {
                b.yesterday.push(decorated);
            } else if (tms !== null && tms >= startOfToday - 6 * DAY) {
                b.week.push(decorated);
            } else if (
                tms !== null &&
                new Date(tms).getMonth() === ref.getMonth() &&
                new Date(tms).getFullYear() === ref.getFullYear()
            ) {
                b.month.push(decorated);
            } else {
                b.older.push(decorated);
            }
        });

        // Most recently overdue first; soonest upcoming first.
        b.overdue.sort((x, y) => new Date(y.activityDateTime) - new Date(x.activityDateTime));
        b.upcoming.sort((x, y) => new Date(x.activityDateTime) - new Date(y.activityDateTime));

        const out = [];
        if (b.overdue.length) {
            out.push({ key: 'overdue', label: 'Overdue', labelClass: 'group-label group-label_overdue', items: b.overdue });
        }
        if (b.upcoming.length) {
            out.push({ key: 'upcoming', label: 'Upcoming', labelClass: 'group-label group-label_upcoming', items: b.upcoming });
        }
        HISTORY_BUCKETS.forEach(([key, label]) => {
            if (b[key].length) {
                out.push({ key, label, labelClass: 'group-label', items: b[key] });
            }
        });
        return out;
    }

    decorate(a) {
        const selected = a.id === this.selectedId;
        return {
            ...a,
            iconName: ICONS[a.type] || ICONS.Task,
            initials: this.initials(a.ownerName),
            relativeTime: this.relativeTime(a.activityDateTime),
            rowClass: selected ? 'activity-row activity-row_selected' : 'activity-row',
            typeClass: `type-badge type-${(a.type || 'task').toLowerCase()}`,
            statusClass: a.isOpen ? 'row-status row-status_open' : 'row-status row-status_done'
        };
    }

    get selectedActivity() {
        const a = this.activities.find((x) => x.id === this.selectedId);
        if (!a) {
            return undefined;
        }
        return {
            ...a,
            iconName: ICONS[a.type] || ICONS.Task,
            typeLabel: a.type === 'Event' ? 'Meeting' : a.type,
            detailTypeClass: `detail-type type-${(a.type || 'task').toLowerCase()}`,
            hasWho: !!a.whoName,
            hasRelatedTo: !!a.relatedToName,
            hasLocation: !!a.location,
            hasStatus: !!a.status,
            hasPriority: !!a.priority,
            hasTeam: !!a.ownerTeam,
            hasLegalEntity: !!a.ownerLegalEntity
        };
    }

    // The headline counts come from the server totals, which already reflect the active structured
    // filters (and are uncapped). The type tab only focuses the list below, not these numbers.
    get summary() {
        const t = this.totals || { totalEmails: 0, totalCalls: 0, totalTasks: 0, totalMeetings: 0 };
        return [
            { key: 'Email', label: 'Emails', count: t.totalEmails, dotClass: 'dot dot-email' },
            { key: 'Call', label: 'Calls', count: t.totalCalls, dotClass: 'dot dot-call' },
            { key: 'Task', label: 'Tasks', count: t.totalTasks, dotClass: 'dot dot-task' },
            { key: 'Event', label: 'Meetings', count: t.totalMeetings, dotClass: 'dot dot-event' }
        ];
    }

    get officeCount() {
        return new Set(this.filteredActivities.map((a) => a.officeName).filter(Boolean)).size;
    }

    get summaryLabel() {
        const total = this.totals ? this.totals.totalAll : 0;
        return `${total} activities across ${this.officeCount} offices`;
    }

    get cappedNote() {
        if (this.totals && this.totals.capped) {
            return `Showing the ${this.activities.length} most recent of ${this.totals.totalAll} — narrow with the filters to find specific items.`;
        }
        return '';
    }

    get typeFilterButtons() {
        return TYPE_FILTERS.map((f) => ({
            ...f,
            buttonClass: this.activeType === f.key ? 'seg-btn seg-btn_on' : 'seg-btn'
        }));
    }

    // Dropdowns are built from the server's full option lists (every owner/office across the firm),
    // so an owner whose activity is all older than the cap is still selectable.
    get officeOptions() {
        const opts = (this.options && this.options.offices) || [];
        return [{ label: 'All offices', value: 'All' }, ...opts.map((o) => ({ label: o.label, value: o.value }))];
    }

    get ownerOptions() {
        const opts = (this.options && this.options.owners) || [];
        return [{ label: 'All owners', value: 'All' }, ...opts.map((o) => ({ label: o.label, value: o.value }))];
    }

    get teamOptions() {
        const opts = (this.options && this.options.teams) || [];
        return [{ label: 'All teams', value: 'All' }, ...opts.map((v) => ({ label: v, value: v }))];
    }

    get legalEntityOptions() {
        const opts = (this.options && this.options.legalEntities) || [];
        return [{ label: 'All legal entities', value: 'All' }, ...opts.map((v) => ({ label: v, value: v }))];
    }

    // Firm-level: does the firm have any activity at all (so we keep the toolbar/filters visible even
    // when the current filter matches nothing)?
    get hasActivities() {
        return this.firmTotal > 0;
    }

    get hasResults() {
        return this.filteredActivities.length > 0;
    }

    // ---- Handlers -------------------------------------------------------

    handleSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    handleTypeClick(event) {
        this.activeType = event.currentTarget.dataset.type;
    }

    handleOfficeChange(event) {
        this.officeFilter = event.detail.value;
        this.reload();
    }

    handleOwnerChange(event) {
        this.ownerFilter = event.detail.value;
        this.reload();
    }

    handleTeamChange(event) {
        this.teamFilter = event.detail.value;
        this.reload();
    }

    handleLegalEntityChange(event) {
        this.legalEntityFilter = event.detail.value;
        this.reload();
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        // Debounce so we query once the user pauses, not on every keystroke.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.clearTimeout(this._searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = window.setTimeout(() => {
            this.loadActivities();
        }, 400);
    }

    handleClear() {
        this.activeType = 'All';
        this.officeFilter = 'All';
        this.ownerFilter = 'All';
        this.teamFilter = 'All';
        this.legalEntityFilter = 'All';
        this.searchKey = '';
        this.reload();
    }

    handleRefresh() {
        this.isRefreshing = true;
        return this.loadActivities().finally(() => {
            this.isRefreshing = false;
        });
    }

    openRecord() {
        if (!this.selectedActivity) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedActivity.id,
                objectApiName: this.selectedActivity.objectApiName,
                actionName: 'view'
            }
        });
    }

    openOffice() {
        if (!this.selectedActivity || !this.selectedActivity.officeId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedActivity.officeId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    // ---- Helpers --------------------------------------------------------

    initials(name) {
        if (!name) {
            return '?';
        }
        return name
            .split(' ')
            .filter(Boolean)
            .slice(0, 2)
            .map((p) => p.charAt(0).toUpperCase())
            .join('');
    }

    relativeTime(value) {
        if (!value) {
            return '';
        }
        const diff = Date.now() - new Date(value).getTime();
        const future = diff < 0;
        const abs = Math.abs(diff);
        if (abs < DAY) {
            return 'Today';
        }
        if (abs < 2 * DAY) {
            return future ? 'Tomorrow' : 'Yesterday';
        }
        let n;
        let unit;
        if (abs < 7 * DAY) {
            n = Math.floor(abs / DAY);
            unit = 'd';
        } else if (abs < 30 * DAY) {
            n = Math.floor(abs / (7 * DAY));
            unit = 'w';
        } else if (abs < 365 * DAY) {
            n = Math.floor(abs / (30 * DAY));
            unit = 'mo';
        } else {
            n = Math.floor(abs / (365 * DAY));
            unit = 'y';
        }
        return future ? `in ${n}${unit}` : `${n}${unit} ago`;
    }

    reduceError(error) {
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        } else if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        } else if (typeof error.message === 'string') {
            return error.message;
        }
        return 'Unknown error';
    }
}
