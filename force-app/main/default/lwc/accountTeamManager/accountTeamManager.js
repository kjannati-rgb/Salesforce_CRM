import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import canManage from '@salesforce/customPermission/Manage_Account_CSMs';
import USER_NAME from '@salesforce/schema/User.Name';
import USER_PHOTO from '@salesforce/schema/User.FullPhotoUrl';
import getTeam from '@salesforce/apex/AccountTeamManagerController.getTeam';
import getRoleConfig from '@salesforce/apex/AccountTeamManagerController.getRoleConfig';
import applyChanges from '@salesforce/apex/AccountTeamManagerController.applyChanges';

const ACCESS_OPTIONS = [
    { label: 'Read only', value: 'Read' },
    { label: 'Read / write', value: 'Edit' },
    { label: 'Private', value: 'None' }
];
const DEFAULT_PHOTO_TOKEN = '/profilephoto/005/';

export default class AccountTeamManager extends LightningElement {
    @api recordId;

    canManage = canManage;
    accessOptions = ACCESS_OPTIONS;

    roleConfig = [];
    members = [];
    pendingAdds = [];
    editingId = null;
    addOpen = false;
    busy = false;

    selectedUserId = null;
    selectedUserName = null;
    selectedUserPhoto = null;
    addRole = null;
    addAccess = 'Read';

    _wiredTeam;

    @wire(getRoleConfig)
    wiredRoles({ data, error }) {
        if (data) {
            this.roleConfig = data;
            if (!this.addRole && data.length) {
                this.addRole = data[0].teamRole;
                this.addAccess = data[0].accountAccess || 'Read';
            }
        } else if (error) {
            this.toast('Could not load role configuration', this.errMsg(error), 'error');
        }
    }

    @wire(getTeam, { accountId: '$recordId' })
    wiredTeam(result) {
        this._wiredTeam = result;
        if (result.data) {
            this.members = result.data.map((m) => ({
                memberId: m.memberId,
                userId: m.userId,
                name: m.name,
                title: m.title,
                photoUrl: m.photoUrl,
                initials: m.initials,
                teamRole: m.teamRole,
                accountAccess: m.accountAccess,
                status: 'current',
                newRole: null
            }));
        } else if (result.error) {
            this.toast('Could not load the account team', this.errMsg(result.error), 'error');
        }
    }

    @wire(getRecord, { recordId: '$selectedUserId', fields: [USER_NAME, USER_PHOTO] })
    wiredSelectedUser({ data }) {
        if (data) {
            this.selectedUserName = getFieldValue(data, USER_NAME);
            const photo = getFieldValue(data, USER_PHOTO);
            this.selectedUserPhoto = photo && !photo.includes(DEFAULT_PHOTO_TOKEN) ? photo : null;
        }
    }

    // ---------- derived ----------
    get roleMap() {
        const map = {};
        this.roleConfig.forEach((r) => {
            map[r.teamRole] = { bg: r.background, text: r.textColor, label: r.label };
        });
        return map;
    }

    get roleComboOptions() {
        return this.roleConfig.map((r) => ({ label: r.label, value: r.teamRole }));
    }

    get displayMembers() {
        return this.members.map((m) => {
            const role = m.newRole || m.teamRole;
            const s = this.roleMap[role] || {};
            return {
                ...m,
                displayRole: role,
                roleLabel: s.label || role,
                roleStyle: `background:${s.bg || '#eef0f2'};color:${s.text || '#5f5e5a'};`,
                accessLabel: this.accessLabel(m.accountAccess),
                isRemoving: m.status === 'removing',
                hasRoleChange: !!m.newRole,
                isEditing: m.memberId === this.editingId,
                rowClass: m.status === 'removing' ? 'atm-row atm-row_removing' : 'atm-row'
            };
        });
    }

    get displayAdds() {
        return this.pendingAdds.map((a) => {
            const s = this.roleMap[a.role] || {};
            return {
                ...a,
                roleLabel: s.label || a.role,
                roleStyle: `background:${s.bg || '#eef0f2'};color:${s.text || '#5f5e5a'};`,
                accessLabel: this.accessLabel(a.access),
                initials: this.initials(a.name)
            };
        });
    }

    get pendingItems() {
        const items = [];
        this.members
            .filter((m) => m.status === 'removing')
            .forEach((m) => items.push({
                key: 'r' + m.memberId, icon: 'utility:dash', variant: 'remove',
                text: `Remove ${m.name} - ${this.roleLabelFor(m.teamRole)}`
            }));
        this.members
            .filter((m) => m.newRole)
            .forEach((m) => items.push({
                key: 'c' + m.memberId, icon: 'utility:change_owner', variant: 'change',
                text: `${m.name}: ${this.roleLabelFor(m.teamRole)} \u2192 ${this.roleLabelFor(m.newRole)}`
            }));
        this.pendingAdds.forEach((a) => items.push({
            key: 'a' + a.key, icon: 'utility:add', variant: 'add',
            text: `Add ${a.name} - ${this.roleLabelFor(a.role)} (${this.accessLabel(a.access)})`
        }));
        return items.map((i) => ({ ...i, css: 'atm-chip atm-chip_' + i.variant }));
    }

    get pendingCount() { return this.pendingItems.length; }
    get hasPending() { return this.pendingCount > 0; }
    get applyLabel() { return `Apply ${this.pendingCount} change${this.pendingCount === 1 ? '' : 's'}`; }
    get memberCount() {
        return this.members.filter((m) => m.status !== 'removing').length + this.pendingAdds.length;
    }
    get isEmpty() { return this.displayMembers.length === 0 && this.pendingAdds.length === 0; }
    get stageDisabled() { return !this.selectedUserId; }
    get showSelectedPreview() { return !!this.selectedUserId; }
    get selectedPreviewInitials() { return this.initials(this.selectedUserName); }
    get userFilter() {
        return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
    }

    // ---------- helpers ----------
    accessLabel(v) {
        const o = ACCESS_OPTIONS.find((x) => x.value === v);
        return o ? o.label : v || '';
    }
    roleLabelFor(role) {
        const s = this.roleMap[role];
        return s ? s.label : role;
    }
    initials(name) {
        if (!name) return '?';
        const p = name.trim().split(/\s+/);
        return (p[0][0] + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e && e.body && e.body.message ? e.body.message : 'Unexpected error.';
    }

    // ---------- events ----------
    openAdd() { this.addOpen = true; }
    cancelAdd() { this.resetAdd(); }
    resetAdd() {
        this.addOpen = false;
        this.selectedUserId = null;
        this.selectedUserName = null;
        this.selectedUserPhoto = null;
    }
    handleUserPick(event) {
        this.selectedUserId = event.detail.recordId || null;
    }
    handleAddRole(event) { this.addRole = event.detail.value; }
    handleAddAccess(event) { this.addAccess = event.detail.value; }

    stageAdd() {
        if (!this.selectedUserId) return;
        this.pendingAdds = [
            ...this.pendingAdds,
            {
                key: Date.now(),
                userId: this.selectedUserId,
                name: this.selectedUserName,
                photoUrl: this.selectedUserPhoto,
                role: this.addRole,
                access: this.addAccess
            }
        ];
        this.resetAdd();
    }
    removeAdd(event) {
        const key = Number(event.currentTarget.dataset.key);
        this.pendingAdds = this.pendingAdds.filter((a) => a.key !== key);
    }
    stageRemove(event) {
        const id = event.currentTarget.dataset.id;
        this.members = this.members.map((m) => (m.memberId === id ? { ...m, status: 'removing' } : m));
    }
    undoRemove(event) {
        const id = event.currentTarget.dataset.id;
        this.members = this.members.map((m) => (m.memberId === id ? { ...m, status: 'current' } : m));
    }
    editRole(event) {
        const id = event.currentTarget.dataset.id;
        this.editingId = this.editingId === id ? null : id;
    }
    changeRole(event) {
        const id = event.currentTarget.dataset.id;
        const value = event.detail.value;
        this.members = this.members.map((m) => {
            if (m.memberId !== id) return m;
            return { ...m, newRole: value === m.teamRole ? null : value };
        });
        this.editingId = null;
    }

    discard() {
        this.members = this.members.map((m) => ({ ...m, status: 'current', newRole: null }));
        this.pendingAdds = [];
        this.editingId = null;
    }

    handleApply() {
        const payload = {
            adds: this.pendingAdds.map((a) => ({
                userId: a.userId, teamRole: a.role, accountAccess: a.access
            })),
            removeIds: this.members.filter((m) => m.status === 'removing').map((m) => m.memberId),
            roleChanges: this.members
                .filter((m) => m.newRole)
                .map((m) => ({ memberId: m.memberId, teamRole: m.newRole }))
        };
        this.busy = true;
        applyChanges({ accountId: this.recordId, changesJson: JSON.stringify(payload) })
            .then(() => {
                this.pendingAdds = [];
                this.editingId = null;
                return refreshApex(this._wiredTeam);
            })
            .then(() => this.toast('Account team updated', 'Changes applied in system context.', 'success'))
            .catch((e) => this.toast('Could not apply changes', this.errMsg(e), 'error'))
            .finally(() => { this.busy = false; });
    }
}
