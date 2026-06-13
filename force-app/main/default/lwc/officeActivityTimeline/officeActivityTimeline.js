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
    error;
    isLoading = true;
    isRefreshing = false;

    selectedId;
    activeType = 'All';
    officeFilter = 'All';
    ownerFilter = 'All';
    teamFilter = 'All';
    legalEntityFilter = 'All';
    searchKey = '';

    // Load imperatively on mount. A @wire on getOfficeActivities left the timeline blank on a
    // record-page tab until the user pressed Refresh; connectedCallback fires once recordId and
    // the design attributes are set, so the data is present on first paint.
    connectedCallback() {
        this.loadActivities();
    }

    async loadActivities() {
        if (!this.recordId) {
            return;
        }
        try {
            const data = await getOfficeActivities({
                accountId: this.recordId,
                monthsBack: this.monthsBack,
                maxRecords: this.maxRecords
            });
            this.activities = (data && data.activities) || [];
            this.totals = data || null;
            this.error = undefined;
            if (this.activities.length && !this.selectedId) {
                this.selectedId = this.activities[0].id;
            }
        } catch (e) {
            this.error = this.reduceError(e);
            this.activities = [];
            this.totals = null;
        } finally {
            this.isLoading = false;
        }
    }

    // ---- Derived data ---------------------------------------------------

    get filteredActivities() {
        const q = this.searchKey.trim().toLowerCase();
        return this.activities.filter((a) => {
            if (this.activeType !== 'All' && a.type !== this.activeType) {
                return false;
            }
            if (this.officeFilter !== 'All' && a.officeName !== this.officeFilter) {
                return false;
            }
            if (this.ownerFilter !== 'All' && a.ownerName !== this.ownerFilter) {
                return false;
            }
            if (this.teamFilter !== 'All' && a.ownerTeam !== this.teamFilter) {
                return false;
            }
            if (this.legalEntityFilter !== 'All' && a.ownerLegalEntity !== this.legalEntityFilter) {
                return false;
            }
            if (q) {
                const haystack = [
                    a.subject,
                    a.description,
                    a.ownerName,
                    a.officeName,
                    a.whoName,
                    a.relatedToName,
                    a.ownerTeam,
                    a.ownerLegalEntity
                ]
                    .filter(Boolean)
                    .join(' ')
                    .toLowerCase();
                if (!haystack.includes(q)) {
                    return false;
                }
            }
            return true;
        });
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

    // With no filters applied, the headline shows the true server-side totals (accurate even when
    // the list is capped at maxRecords). Once any filter is on, it reflects the loaded filtered set.
    get isFiltered() {
        return (
            this.activeType !== 'All' ||
            this.officeFilter !== 'All' ||
            this.ownerFilter !== 'All' ||
            this.teamFilter !== 'All' ||
            this.legalEntityFilter !== 'All' ||
            this.searchKey.trim() !== ''
        );
    }

    get summary() {
        let counts;
        if (!this.isFiltered && this.totals) {
            counts = {
                Email: this.totals.totalEmails,
                Call: this.totals.totalCalls,
                Task: this.totals.totalTasks,
                Event: this.totals.totalMeetings
            };
            return [
                { key: 'Email', label: 'Emails', count: counts.Email, dotClass: 'dot dot-email' },
                { key: 'Call', label: 'Calls', count: counts.Call, dotClass: 'dot dot-call' },
                { key: 'Task', label: 'Tasks', count: counts.Task, dotClass: 'dot dot-task' },
                { key: 'Event', label: 'Meetings', count: counts.Event, dotClass: 'dot dot-event' }
            ];
        }
        counts = { Email: 0, Call: 0, Task: 0, Event: 0 };
        this.filteredActivities.forEach((a) => {
            if (counts[a.type] !== undefined) {
                counts[a.type] += 1;
            }
        });
        return [
            { key: 'Email', label: 'Emails', count: counts.Email, dotClass: 'dot dot-email' },
            { key: 'Call', label: 'Calls', count: counts.Call, dotClass: 'dot dot-call' },
            { key: 'Task', label: 'Tasks', count: counts.Task, dotClass: 'dot dot-task' },
            { key: 'Event', label: 'Meetings', count: counts.Event, dotClass: 'dot dot-event' }
        ];
    }

    get officeCount() {
        return new Set(this.filteredActivities.map((a) => a.officeName).filter(Boolean)).size;
    }

    get summaryLabel() {
        const total =
            !this.isFiltered && this.totals ? this.totals.totalAll : this.filteredActivities.length;
        return `${total} activities across ${this.officeCount} offices`;
    }

    get cappedNote() {
        if (!this.isFiltered && this.totals && this.totals.capped) {
            return `Showing the ${this.activities.length} most recent of ${this.totals.totalAll} — filter to narrow.`;
        }
        return '';
    }

    get typeFilterButtons() {
        return TYPE_FILTERS.map((f) => ({
            ...f,
            buttonClass: this.activeType === f.key ? 'seg-btn seg-btn_on' : 'seg-btn'
        }));
    }

    get officeOptions() {
        return this.buildOptions('officeName', 'All offices');
    }

    get ownerOptions() {
        return this.buildOptions('ownerName', 'All owners');
    }

    get teamOptions() {
        return this.buildOptions('ownerTeam', 'All teams');
    }

    get legalEntityOptions() {
        return this.buildOptions('ownerLegalEntity', 'All legal entities');
    }

    buildOptions(key, allLabel) {
        const values = [...new Set(this.activities.map((a) => a[key]).filter(Boolean))].sort();
        return [{ label: allLabel, value: 'All' }, ...values.map((v) => ({ label: v, value: v }))];
    }

    get hasActivities() {
        return this.activities.length > 0;
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
    }

    handleOwnerChange(event) {
        this.ownerFilter = event.detail.value;
    }

    handleTeamChange(event) {
        this.teamFilter = event.detail.value;
    }

    handleLegalEntityChange(event) {
        this.legalEntityFilter = event.detail.value;
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
    }

    handleClear() {
        this.activeType = 'All';
        this.officeFilter = 'All';
        this.ownerFilter = 'All';
        this.teamFilter = 'All';
        this.legalEntityFilter = 'All';
        this.searchKey = '';
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
