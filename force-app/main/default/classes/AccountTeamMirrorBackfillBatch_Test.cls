@IsTest
private class AccountTeamMirrorBackfillBatch_Test {

    @IsTest
    static void backfills_existing_membership_into_mirror_field() {
        List<Account_Team_Role_Config__mdt> cfg = [
            SELECT Team_Role__c, Mirror_To_Account_Field__c FROM Account_Team_Role_Config__mdt
            WHERE Active__c = true AND Mirror_To_Account_Field__c != null LIMIT 1];
        if (cfg.isEmpty()) {
            return; // no mirrored role configured; nothing to back-fill
        }
        String role = cfg[0].Team_Role__c;
        String fld = cfg[0].Mirror_To_Account_Field__c;

        List<User> holders = [SELECT Id FROM User
            WHERE IsActive = true AND UserType = 'Standard'
              AND Profile.PermissionsModifyAllData = false AND Id != :UserInfo.getUserId() LIMIT 1];
        System.assertEquals(1, holders.size(), 'Need one standard user');
        User holder = holders[0];

        Account acct = new Account(Name = 'Backfill Co');
        insert acct;
        Id acctId = acct.Id;

        // Member exists (trigger stamps the field) ...
        insert new AccountTeamMember(
            AccountId = acctId, UserId = holder.Id, TeamMemberRole = role, AccountAccessLevel = 'Edit');

        // ... but simulate a team that pre-dates the trigger: blank the mirror field.
        Account stale = new Account(Id = acctId);
        stale.put(fld, null);
        update stale;
        List<Account> pre = Database.query('SELECT ' + fld + ' FROM Account WHERE Id = :acctId');
        System.assertEquals(null, pre[0].get(fld), 'Precondition: mirror field is blank');

        Test.startTest();
        Database.executeBatch(new AccountTeamMirrorBackfillBatch(), 200);
        Test.stopTest();

        List<Account> post = Database.query('SELECT ' + fld + ' FROM Account WHERE Id = :acctId');
        System.assertEquals(holder.Id, post[0].get(fld),
            'Backfill should stamp the existing member onto the mirror field');
    }
}
