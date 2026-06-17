@IsTest
private class AccountTeamManagerController_Test {

    // Returns existing active standard users that lack Modify All. We deliberately
    // do NOT insert new User records: this org has an after-save flow
    // ("User: Create Contact from User") that fires on every User insert, has no
    // bypass, and references a hard-coded Account - so a User insert blows up inside
    // a data-isolated test. Querying existing users sidesteps that entirely (User is
    // visible in tests without SeeAllData), and "no Modify All" keeps the
    // system-context assertion below honest - none of these users is the account
    // owner, above the owner in the hierarchy, or holds Modify All.
    private static List<User> pickStandardUsers(Integer count) {
        return [
            SELECT Id FROM User
            WHERE IsActive = true
              AND UserType = 'Standard'
              AND Profile.PermissionsModifyAllData = false
              AND Id != :UserInfo.getUserId()
            LIMIT :count];
    }

    private static void grantManagePermission(Id userId) {
        PermissionSet ps = new PermissionSet(
            Name = 'ATM_Test_PS_' + Math.abs(Crypto.getRandomInteger()),
            Label = 'ATM Test PS');
        insert ps;
        CustomPermission cp = [SELECT Id FROM CustomPermission
                               WHERE DeveloperName = 'Manage_Account_CSMs' LIMIT 1];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    }

    private static String roleAt(Integer index) {
        Integer i = 0;
        for (Schema.PicklistEntry e : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (!e.isActive()) continue;
            if (i == index) return e.getValue();
            i++;
        }
        return null;
    }

    @IsTest
    static void blocks_without_permission() {
        Account a = new Account(Name = 'No-Perm Co');
        insert a;
        Boolean threw = false;
        Test.startTest();
        try {
            AccountTeamManagerController.applyChanges(a.Id, '{}');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw,
            'Expected a permission failure when the running user lacks Manage_Account_CSMs');
    }

    @IsTest
    static void add_change_remove_roundtrip() {
        String roleA = roleAt(0);
        String roleB = roleAt(1) == null ? roleA : roleAt(1);
        System.assertNotEquals(null, roleA, 'Org has no active Team Role picklist values');

        List<User> pool = pickStandardUsers(2);
        System.assertEquals(2, pool.size(),
            'Need two existing active standard users (no Modify All) to run this test');
        User runner = pool[0];
        User member = pool[1];

        // Grant the manage permission to runner. Permission-set DML is setup-object
        // DML, so isolate it in runAs to avoid MIXED_DML with the Account insert below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            grantManagePermission(runner.Id);
        }

        Account acct = new Account(Name = 'Roundtrip Co');
        insert acct; // owned by the running admin, NOT by "runner" - proves system-context path

        Test.startTest();
        System.runAs(runner) {
            String addJson = JSON.serialize(new Map<String, Object>{
                'adds' => new List<Object>{
                    new Map<String, Object>{
                        'userId' => member.Id, 'teamRole' => roleA, 'accountAccess' => 'Edit'
                    }
                }
            });
            List<AccountTeamManagerController.TeamMemberView> afterAdd =
                AccountTeamManagerController.applyChanges(acct.Id, addJson);
            System.assertEquals(1, afterAdd.size(), 'One member expected after add');
            Id memberRecId = afterAdd[0].memberId;

            String changeJson = JSON.serialize(new Map<String, Object>{
                'roleChanges' => new List<Object>{
                    new Map<String, Object>{ 'memberId' => memberRecId, 'teamRole' => roleB }
                }
            });
            List<AccountTeamManagerController.TeamMemberView> afterChange =
                AccountTeamManagerController.applyChanges(acct.Id, changeJson);
            System.assertEquals(roleB, afterChange[0].teamRole, 'Role should be updated');

            String removeJson = JSON.serialize(new Map<String, Object>{
                'removeIds' => new List<Id>{ memberRecId }
            });
            List<AccountTeamManagerController.TeamMemberView> afterRemove =
                AccountTeamManagerController.applyChanges(acct.Id, removeJson);
            System.assertEquals(0, afterRemove.size(), 'Member should be removed');
        }
        Test.stopTest();
    }

    @IsTest
    static void reads_return_data() {
        Account a = new Account(Name = 'Reads Co');
        insert a;
        Test.startTest();
        List<AccountTeamManagerController.RoleOption> roles = AccountTeamManagerController.getRoleConfig();
        List<AccountTeamManagerController.TeamMemberView> team = AccountTeamManagerController.getTeam(a.Id);
        Test.stopTest();
        System.assertNotEquals(null, roles, 'Role config should not be null');
        System.assertEquals(0, team.size(), 'New account has no team members');
    }
}
