import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPanelData from '@salesforce/apex/DealContactsController.getPanelData';
import setRoleContact from '@salesforce/apex/DealContactsController.setRoleContact';
import copyFromPreviousQuote from '@salesforce/apex/DealContactsController.copyFromPreviousQuote';
import searchFamilyContacts from '@salesforce/apex/DealContactsController.searchFamilyContacts';

const ROLE_META = {
    primary: { label: 'Primary Contact', icon: 'utility:user', alwaysRequired: true },
    invoice: { label: 'Invoice Contact', icon: 'utility:money', alwaysRequired: false },
    creative: { label: 'Creative Contact', icon: 'utility:image', alwaysRequired: false },
    event: { label: 'Event Logistics Contact', icon: 'utility:event', alwaysRequired: false },
    signatory: { label: 'Signatory Contact', icon: 'utility:signature', alwaysRequired: false }
};

const SOURCE_META = {
    synced: { label: 'Synced from Contact Role', variant: 'success' },
    renewal: { label: 'Carried from previous quote', variant: 'brand' },
    'same-as-primary': { label: 'Set same as Primary', variant: 'inverse' },
    manual: { label: 'Manually set', variant: 'inverse' }
};

const SEARCH_DEBOUNCE_MS = 300;

export default class DealContacts extends LightningElement {
    @api recordId; // SBQQ__Quote__c Id, provided by the record page

    wiredResult;
    panel;
    error;
    activeRoleKey; // which row's picker is open, if any
    saving = false;

    searchResultsByRole = {}; // roleKey -> array of ContactSearchResult
    searchingRoleKey; // roleKey currently awaiting a search response, if any
    searchTimeoutId;

    @wire(getPanelData, { quoteId: '$recordId' })
    wiredPanel(result) {
        this.wiredResult = result;
        if (result.data) {
            this.panel = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.panel = undefined;
        }
    }

    get isLoading() {
        return !this.panel && !this.error;
    }

    get roleRows() {
        if (!this.panel) return [];
        return Object.keys(ROLE_META).map((key) => {
            const meta = ROLE_META[key];
            const role = this.panel.roles[key] || {};
            const required = meta.alwaysRequired || (this.panel.hasAlmEvent && (key === 'invoice' || key === 'event'));
            const source = role.source ? SOURCE_META[role.source] : undefined;
            const rawResults = this.searchResultsByRole[key] || [];
            return {
                key,
                label: meta.label,
                icon: meta.icon,
                required,
                contactId: role.contactId,
                name: role.name,
                title: role.title,
                isSet: !!role.contactId,
                sourceLabel: source ? source.label : '',
                sourceVariant: source ? source.variant : 'inverse',
                showSameAsPrimary: key !== 'primary' && !role.contactId && !!(this.panel.roles.primary && this.panel.roles.primary.contactId),
                isPickerOpen: this.activeRoleKey === key,
                isSearching: this.searchingRoleKey === key,
                searchResults: rawResults.map((r) => ({
                    contactId: r.contactId,
                    name: r.name,
                    subtitle: [r.sameOffice ? 'This office' : 'Other office in the firm', r.title, r.accountName].filter(Boolean).join(' · ')
                }))
            };
        });
    }

    get roleCount() {
        return Object.keys(ROLE_META).length;
    }

    get syncedCount() {
        return this.roleRows.filter((r) => r.isSet).length;
    }

    get counterLabel() {
        return `${this.syncedCount} / ${this.roleCount} synced`;
    }

    get counterBadgeClass() {
        return this.syncedCount === this.roleCount ? 'slds-badge slds-theme_success' : 'slds-badge';
    }

    get showRenewalBanner() {
        return !!(this.panel && this.panel.isRenewal && this.panel.previousQuoteId && this.syncedCount < this.roleCount);
    }

    get renewalBannerText() {
        if (!this.panel) return '';
        return `This quote renews ${this.panel.previousQuoteLabel}. Any contact already on file there can be carried over.`;
    }

    handleTogglePicker(event) {
        const key = event.currentTarget.dataset.role;
        if (this.activeRoleKey === key) {
            this.activeRoleKey = undefined;
            return;
        }
        this.activeRoleKey = key;
        this.searchResultsByRole = { ...this.searchResultsByRole, [key]: [] };
        this.runSearch(key, '');
    }

    handleSameAsPrimary(event) {
        const key = event.currentTarget.dataset.role;
        const primaryId = this.panel.roles.primary && this.panel.roles.primary.contactId;
        if (!primaryId) return;
        this.applyRole(key, primaryId, 'same-as-primary');
    }

    handleSearchInput(event) {
        const key = event.currentTarget.dataset.role;
        const term = event.target.value;
        window.clearTimeout(this.searchTimeoutId);
        this.searchTimeoutId = window.setTimeout(() => {
            this.runSearch(key, term);
        }, SEARCH_DEBOUNCE_MS);
    }

    runSearch(roleKey, term) {
        this.searchingRoleKey = roleKey;
        searchFamilyContacts({ quoteId: this.recordId, searchTerm: term })
            .then((results) => {
                if (this.activeRoleKey !== roleKey) return; // popover closed or switched before this resolved
                this.searchResultsByRole = { ...this.searchResultsByRole, [roleKey]: results };
            })
            .catch((err) => this.notifyError(err))
            .finally(() => {
                if (this.searchingRoleKey === roleKey) {
                    this.searchingRoleKey = undefined;
                }
            });
    }

    handleSearchResultClick(event) {
        const key = event.currentTarget.dataset.role;
        const contactId = event.currentTarget.dataset.contactId;
        this.applyRole(key, contactId, 'manual');
    }

    applyRole(roleKey, contactId, source) {
        this.saving = true;
        setRoleContact({ quoteId: this.recordId, role: roleKey, contactId, source })
            .then(() => {
                this.activeRoleKey = undefined;
                return refreshApex(this.wiredResult);
            })
            .catch((err) => this.notifyError(err))
            .finally(() => {
                this.saving = false;
            });
    }

    handleCopyFromPrevious() {
        this.saving = true;
        copyFromPreviousQuote({ quoteId: this.recordId })
            .then((appliedRoles) => {
                const appliedCount = Object.keys(appliedRoles || {}).length;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Contacts copied',
                        message: appliedCount
                            ? `Carried ${appliedCount} contact(s) from the previous quote.`
                            : 'The previous quote had no contacts set to carry over.',
                        variant: 'success'
                    })
                );
                return refreshApex(this.wiredResult);
            })
            .catch((err) => this.notifyError(err))
            .finally(() => {
                this.saving = false;
            });
    }

    notifyError(err) {
        const message = (err && err.body && err.body.message) || 'Something went wrong saving this contact.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }
}
