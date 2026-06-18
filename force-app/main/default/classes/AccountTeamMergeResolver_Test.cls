@IsTest
private class AccountTeamMergeResolver_Test {

    @IsTest
    static void merge_collapses_duplicate_single_holder_to_one() {
        List<Account_Team_Role_Config__mdt> cfg = [
            SELECT Team_Role__c, Mirror_To_Account_Field__c FROM Account_Team_Role_Config__mdt
            WHERE Single_Holder__c = true AND Mirror_To_Account_Field__c != null
              AND Active__c = true LIMIT 1];
        if (cfg.isEmpty()) {
            return; // no single-holder + mirrored role configured
        }
        String role = cfg[0].Team_Role__c;
        String fld = cfg[0].Mirror_To_Account_Field__c;

        List<User> us = [SELECT Id FROM User
            WHERE IsActive = true AND UserType = 'Standard'
              AND Profile.PermissionsModifyAllData = false AND Id != :UserInfo.getUserId() LIMIT 2];
        System.assertEquals(2, us.size(), 'Need two standard users');

        Account master = new Account(Name = 'Merge Master');
        Account loser = new Account(Name = 'Merge Loser');
        insert new List<Account>{ master, loser };
        Id masterId = master.Id;

        // Different people in the SAME single-holder role on the two accounts.
        insert new AccountTeamMember(
            AccountId = master.Id, UserId = us[0].Id, TeamMemberRole = role, AccountAccessLevel = 'Edit');
        insert new AccountTeamMember(
            AccountId = loser.Id, UserId = us[1].Id, TeamMemberRole = role, AccountAccessLevel = 'Edit');

        Test.startTest();
        merge master loser; // reparents loser's holder onto master -> safeguard must resolve it
        Test.stopTest();

        List<AccountTeamMember> holders = [
            SELECT Id FROM AccountTeamMember WHERE AccountId = :masterId AND TeamMemberRole = :role];
        System.assertEquals(1, holders.size(),
            'After-merge safeguard should leave exactly one holder of the single-holder role');

        List<Account> a = Database.query('SELECT ' + fld + ' FROM Account WHERE Id = :masterId');
        System.assertNotEquals(null, a[0].get(fld),
            'Mirror field should reflect the surviving holder after the merge is resolved');
    }
}
