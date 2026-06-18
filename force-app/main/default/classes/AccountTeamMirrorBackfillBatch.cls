/**
 * One-time backfill for the reportable Account CSM mirror fields.
 *
 * The AccountTeamMemberTrigger keeps Account.<mirror field> in sync from the moment
 * it is deployed, but accounts whose team was set up BEFORE that stay blank until
 * their team next changes. This batch walks existing AccountTeamMember records in the
 * mirrored roles and stamps the matching Account field, so reports are accurate on
 * day one.
 *
 * Config-driven (Account_Team_Role_Config__mdt.Mirror_To_Account_Field__c) and
 * bulk-safe. Set-only: it populates from current membership and does not clear
 * fields (existing values start null at backfill time, and the trigger owns ongoing
 * sync). Run once after deploy:  Database.executeBatch(new AccountTeamMirrorBackfillBatch(), 200);
 *
 * In a large org, run inside a controlled window - the Account updates fire the org's
 * Account automation; set the appropriate Application_Settings__c bypass if needed.
 */
public without sharing class AccountTeamMirrorBackfillBatch implements Database.Batchable<SObject> {

    private final Map<String, String> fieldByRole;

    public AccountTeamMirrorBackfillBatch() {
        fieldByRole = new Map<String, String>();
        for (Account_Team_Role_Config__mdt c : [
                SELECT Team_Role__c, Mirror_To_Account_Field__c
                FROM Account_Team_Role_Config__mdt
                WHERE Active__c = true AND Mirror_To_Account_Field__c != null]) {
            fieldByRole.put(c.Team_Role__c, c.Mirror_To_Account_Field__c);
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<String> roles = fieldByRole.keySet();
        return Database.getQueryLocator([
            SELECT AccountId, UserId, TeamMemberRole
            FROM AccountTeamMember
            WHERE TeamMemberRole IN :roles]);
    }

    public void execute(Database.BatchableContext bc, List<AccountTeamMember> scope) {
        Map<Id, Account> toUpdate = new Map<Id, Account>();
        for (AccountTeamMember m : scope) {
            String fld = fieldByRole.get(m.TeamMemberRole);
            if (fld == null) {
                continue;
            }
            Account a = toUpdate.containsKey(m.AccountId)
                ? toUpdate.get(m.AccountId) : new Account(Id = m.AccountId);
            a.put(fld, m.UserId);
            toUpdate.put(m.AccountId, a);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate.values();
        }
    }

    public void finish(Database.BatchableContext bc) {
        // no-op
    }
}
