import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPanelData from '@salesforce/apex/DealContactsController.getPanelData';
import setRoleContact from '@salesforce/apex/DealContactsController.setRoleContact';
import copyFromPreviousQuote from '@salesforce/apex/DealContactsController.copyFromPreviousQuote';

const ROLE_META = {
    primary: { label: 'Primary Contact', icon: 'utility:user', alwaysRequired: true },
    invoice: { label: 'Invoice Contact', icon: 'utility:money', alwaysRequired: false },
    creative: { label: 'Creative Contact', icon: 'utility:image', alwaysRequired: false },
    event: { label: 'Event Logistics Contact', icon: 'utility:event', alwaysRequired: false }
};

const SOURCE_META = {
    synced: { label: 'Synced from Contact Role', variant: 'success' },
    renewal: { label: 'Carried from previous quote', variant: 'brand' },
    'same-as-primary': { label: 'Set same as Primary', variant: 'inverse' },
    manual: { label: 'Manually set', variant: 'inverse' }
};

export default class DealContacts extends LightningElement {
    @api recordId; // SBQQ__Quote__c Id, provided by the record page

    wiredResult;
    panel;
    error;
    activeRoleKey; // which row's picker is open, if any
    saving = false;

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

    get accountFilter() {
        if (!this.panel) return undefined;
        return {
            criteria: [{ fieldPath: 'AccountId', operator: 'eq', value: this.panel.accountId }],
            filterLogic: '1'
        };
    }

    get roleRows() {
        if (!this.panel) return [];
        return Object.keys(ROLE_META).map((key) => {
            const meta = ROLE_META[key];
            const role = this.panel.roles[key] || {};
            const required = meta.alwaysRequired || (this.panel.hasAlmEvent && (key === 'invoice' || key === 'event'));
            const source = role.source ? SOURCE_META[role.source] : undefined;
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
                rowClass: 'role-row' + (this.activeRoleKey === key ? ' role-row_active' : '')
            };
        });
    }

    get syncedCount() {
        return this.roleRows.filter((r) => r.isSet).length;
    }

    get counterLabel() {
        return `${this.syncedCount} / 4 synced`;
    }

    get counterVariant() {
        return this.syncedCount === 4 ? 'success' : 'inverse';
    }

    get counterBadgeClass() {
        return this.syncedCount === 4 ? 'slds-badge slds-theme_success' : 'slds-badge';
    }

    get showRenewalBanner() {
        return !!(this.panel && this.panel.isRenewal && this.panel.previousQuoteId && this.syncedCount < 4);
    }

    get renewalBannerText() {
        if (!this.panel) return '';
        return `This quote renews ${this.panel.previousQuoteLabel}. Any Primary, Invoice, Creative or Event Logistics contact already on file there can be carried over.`;
    }

    handleTogglePicker(event) {
        const key = event.currentTarget.dataset.role;
        this.activeRoleKey = this.activeRoleKey === key ? undefined : key;
    }

    handleSameAsPrimary(event) {
        const key = event.currentTarget.dataset.role;
        const primaryId = this.panel.roles.primary && this.panel.roles.primary.contactId;
        if (!primaryId) return;
        this.applyRole(key, primaryId, 'same-as-primary');
    }

    handlePick(event) {
        const key = event.currentTarget.dataset.role;
        const contactId = event.detail.recordId;
        if (!contactId) return;
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
