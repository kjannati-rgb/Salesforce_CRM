/**
 * Restores the single-holder invariant after an ACCOUNT MERGE.
 *
 * On merge, Salesforce reparents the losing accounts' AccountTeamMember rows onto
 * the surviving (master) account WITHOUT firing the AccountTeamMember trigger - so
 * the single-holder guardrail is bypassed and the master can end up with more than
 * one holder of a single-holder role, with a stale mirror field. Verified in
 * FULLUAT 2026-06-17 (a merge left two ALM CSMs on the master).
 *
 * AccountTeamMergeTrigger hands the surviving master(s) here. We keep the
 * longest-standing holder per single-holder role (earliest CreatedDate) and delete
 * the rest. Those deletes fire the normal AccountTeamMember trigger, which writes
 * the Remove audit row and re-syncs the Account mirror field - so the resolution is
 * itself audited and the mirror self-heals. The "keep oldest" rule is deterministic
 * and easily changed (one ORDER BY) if the business prefers another tie-break.
 */
public without sharing class AccountTeamMergeResolver {

    public static void resolve(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        Application_Settings__c settings = Application_Settings__c.getInstance();
        if (settings != null && settings.Disable_Triggers__c == true) {
            return;
        }

        Set<String> singleRoles = new Set<String>();
        for (Account_Team_Role_Config__mdt c : [
                SELECT Team_Role__c FROM Account_Team_Role_Config__mdt
                WHERE Active__c = true AND Single_Holder__c = true]) {
            singleRoles.add(c.Team_Role__c);
        }
        if (singleRoles.isEmpty()) {
            return;
        }

        // Oldest holder per (account, single-holder role) is kept; later ones are extras.
        Map<Id, Set<String>> kept = new Map<Id, Set<String>>();
        List<AccountTeamMember> extras = new List<AccountTeamMember>();
        for (AccountTeamMember m : [
                SELECT Id, AccountId, TeamMemberRole FROM AccountTeamMember
                WHERE AccountId IN :accountIds AND TeamMemberRole IN :singleRoles
                ORDER BY CreatedDate ASC, Id ASC]) {
            if (!kept.containsKey(m.AccountId)) {
                kept.put(m.AccountId, new Set<String>());
            }
            if (kept.get(m.AccountId).contains(m.TeamMemberRole)) {
                extras.add(m);
            } else {
                kept.get(m.AccountId).add(m.TeamMemberRole);
            }
        }
        if (!extras.isEmpty()) {
            delete extras; // fires AccountTeamMemberTrigger -> Remove audit + mirror re-sync
        }
    }
}
