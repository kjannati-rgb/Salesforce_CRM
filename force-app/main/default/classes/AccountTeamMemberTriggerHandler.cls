/**
 * Data-layer invariants for AccountTeamMember - so they hold for EVERY entry point
 * (this org's Account Team Manager LWC, the native related list, data loader, API,
 * other Apex), not just the LWC controller. ChurnZero READS account teams from
 * Salesforce, so the team is the source of truth for CS ownership; this keeps it
 * clean and reportable without changing what ChurnZero consumes.
 *
 *   1. Single-holder guardrail (before insert/update): blocks a change that would
 *      leave more than one active member in a role flagged Single_Holder__c on an
 *      account - evaluated on the RESULTING state, so a swap is still allowed.
 *   2. Audit trail (after): one Account_Team_Change__c row per add / remove /
 *      role-change; actor + timestamp via CreatedBy / CreatedDate.
 *   3. Reportable mirror (after): keeps the configured Account User-lookup field
 *      (Mirror_To_Account_Field__c) in sync with the active holder, so account-team
 *      composition is reportable (AccountTeamMember itself is not).
 *
 * Runs WITHOUT SHARING so it can maintain accounts the acting user does not own.
 * Honours the org bypass standard: Disable_Triggers__c short-circuits everything;
 * Disable_Validation_Rules__c skips only the guardrail (audit + mirror still run).
 */
public without sharing class AccountTeamMemberTriggerHandler {

    public static void run() {
        Application_Settings__c settings = Application_Settings__c.getInstance();
        if (settings != null && settings.Disable_Triggers__c == true) {
            return;
        }

        List<Account_Team_Role_Config__mdt> cfgs = [
            SELECT Team_Role__c, Single_Holder__c, Mirror_To_Account_Field__c
            FROM Account_Team_Role_Config__mdt
            WHERE Active__c = true];

        if (Trigger.isBefore) {
            Boolean skipGuardrail = (settings != null && settings.Disable_Validation_Rules__c == true);
            if (!skipGuardrail && (Trigger.isInsert || Trigger.isUpdate)) {
                enforceSingleHolder(cfgs);
            }
            return;
        }

        // after insert / update / delete / undelete
        writeAudit();
        syncMirror(cfgs);
    }

    // -------------------- 1. single-holder guardrail --------------------

    private static void enforceSingleHolder(List<Account_Team_Role_Config__mdt> cfgs) {
        Set<String> singleRoles = new Set<String>();
        for (Account_Team_Role_Config__mdt c : cfgs) {
            if (c.Single_Holder__c == true) {
                singleRoles.add(c.Team_Role__c);
            }
        }
        if (singleRoles.isEmpty()) {
            return;
        }

        List<AccountTeamMember> newList = (List<AccountTeamMember>) Trigger.new;
        Set<Id> acctIds = new Set<Id>();
        for (AccountTeamMember m : newList) {
            if (singleRoles.contains(m.TeamMemberRole)) {
                acctIds.add(m.AccountId);
            }
        }
        if (acctIds.isEmpty()) {
            return;
        }

        // Records being updated in this transaction are superseded by their Trigger.new value.
        Set<Id> updatingIds = (Trigger.isUpdate && Trigger.newMap != null)
            ? Trigger.newMap.keySet() : new Set<Id>();

        // account -> role -> distinct user ids, in the RESULTING state
        Map<Id, Map<String, Set<Id>>> holders = new Map<Id, Map<String, Set<Id>>>();
        for (AccountTeamMember db : [
                SELECT Id, AccountId, UserId, TeamMemberRole FROM AccountTeamMember
                WHERE AccountId IN :acctIds AND TeamMemberRole IN :singleRoles]) {
            if (updatingIds.contains(db.Id)) {
                continue;
            }
            addHolder(holders, db.AccountId, db.TeamMemberRole, db.UserId);
        }
        for (AccountTeamMember m : newList) {
            if (singleRoles.contains(m.TeamMemberRole)) {
                addHolder(holders, m.AccountId, m.TeamMemberRole, m.UserId);
            }
        }

        for (AccountTeamMember m : newList) {
            if (!singleRoles.contains(m.TeamMemberRole)) {
                continue;
            }
            Map<String, Set<Id>> byRole = holders.get(m.AccountId);
            Set<Id> users = (byRole == null) ? null : byRole.get(m.TeamMemberRole);
            if (users != null && users.size() > 1) {
                m.addError('Only one "' + m.TeamMemberRole + '" is allowed per account. '
                    + 'This account already has a different holder - remove or re-role them first.');
            }
        }
    }

    private static void addHolder(Map<Id, Map<String, Set<Id>>> holders, Id acct, String role, Id userId) {
        if (!holders.containsKey(acct)) {
            holders.put(acct, new Map<String, Set<Id>>());
        }
        Map<String, Set<Id>> byRole = holders.get(acct);
        if (!byRole.containsKey(role)) {
            byRole.put(role, new Set<Id>());
        }
        byRole.get(role).add(userId);
    }

    // -------------------- 2. audit trail --------------------

    private static void writeAudit() {
        List<Account_Team_Change__c> rows = new List<Account_Team_Change__c>();
        if (Trigger.isInsert || Trigger.isUndelete) {
            for (AccountTeamMember m : (List<AccountTeamMember>) Trigger.new) {
                rows.add(row(m.AccountId, m.UserId, 'Add', null, m.TeamMemberRole, m.AccountAccessLevel));
            }
        } else if (Trigger.isDelete) {
            for (AccountTeamMember m : (List<AccountTeamMember>) Trigger.old) {
                rows.add(row(m.AccountId, m.UserId, 'Remove', m.TeamMemberRole, null, null));
            }
        } else if (Trigger.isUpdate) {
            for (AccountTeamMember m : (List<AccountTeamMember>) Trigger.new) {
                AccountTeamMember prior = (AccountTeamMember) Trigger.oldMap.get(m.Id);
                if (prior.TeamMemberRole != m.TeamMemberRole) {
                    rows.add(row(m.AccountId, m.UserId, 'Role Change', prior.TeamMemberRole, m.TeamMemberRole, null));
                }
            }
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
    }

    private static Account_Team_Change__c row(Id accountId, Id userId, String changeType,
            String oldRole, String newRole, String access) {
        return new Account_Team_Change__c(
            Account__c        = accountId,
            Team_Member__c    = userId,
            Change_Type__c    = changeType,
            Previous_Role__c  = oldRole,
            New_Role__c       = newRole,
            Account_Access__c = access);
    }

    // -------------------- 3. reportable Account mirror --------------------

    private static void syncMirror(List<Account_Team_Role_Config__mdt> cfgs) {
        Map<String, String> fieldByRole = new Map<String, String>();
        for (Account_Team_Role_Config__mdt c : cfgs) {
            if (String.isNotBlank(c.Mirror_To_Account_Field__c)) {
                fieldByRole.put(c.Team_Role__c, c.Mirror_To_Account_Field__c);
            }
        }
        if (fieldByRole.isEmpty()) {
            return;
        }

        Set<Id> acctIds = affectedAccountIds();
        if (acctIds.isEmpty()) {
            return;
        }

        Set<String> mirroredRoles = fieldByRole.keySet();
        // current holder per (account, mirrored role) AFTER the DML
        Map<Id, Map<String, Id>> holderByAcctRole = new Map<Id, Map<String, Id>>();
        for (AccountTeamMember m : [
                SELECT AccountId, UserId, TeamMemberRole FROM AccountTeamMember
                WHERE AccountId IN :acctIds AND TeamMemberRole IN :mirroredRoles]) {
            if (!holderByAcctRole.containsKey(m.AccountId)) {
                holderByAcctRole.put(m.AccountId, new Map<String, Id>());
            }
            holderByAcctRole.get(m.AccountId).put(m.TeamMemberRole, m.UserId);
        }

        List<String> fields = new List<String>(new Set<String>(fieldByRole.values()));
        String soql = 'SELECT Id, ' + String.join(fields, ', ') + ' FROM Account WHERE Id IN :acctIds';
        List<Account> toUpdate = new List<Account>();
        for (Account a : (List<Account>) Database.query(soql)) {
            Boolean dirty = false;
            Map<String, Id> roleHolders = holderByAcctRole.containsKey(a.Id)
                ? holderByAcctRole.get(a.Id) : new Map<String, Id>();
            for (String role : fieldByRole.keySet()) {
                String fld = fieldByRole.get(role);
                Object desired = roleHolders.get(role); // null if no current holder
                if (a.get(fld) != desired) {
                    a.put(fld, desired);
                    dirty = true;
                }
            }
            if (dirty) {
                toUpdate.add(a);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate; // only accounts whose mirror actually changed
        }
    }

    private static Set<Id> affectedAccountIds() {
        Set<Id> ids = new Set<Id>();
        if (Trigger.new != null) {
            for (SObject s : Trigger.new) {
                Id a = (Id) s.get('AccountId');
                if (a != null) { ids.add(a); }
            }
        }
        if (Trigger.old != null) {
            for (SObject s : Trigger.old) {
                Id a = (Id) s.get('AccountId');
                if (a != null) { ids.add(a); }
            }
        }
        return ids;
    }
}
