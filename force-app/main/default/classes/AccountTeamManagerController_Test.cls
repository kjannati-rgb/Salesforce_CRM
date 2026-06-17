@IsTest
private class AccountTeamManagerController_Test {

    private static User makeStandardUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(DateTime.now().getTime()) + Math.abs(Crypto.getRandomInteger());
        return new User(
            FirstName        = 'ATM',
            LastName         = 'Tester',
            Alias            = 'atmt',
            Email            = 'atm.tester@example.com.invalid',
            Username         = 'atm.tester.' + uniq + '@example.com.invalid',
            ProfileId        = p.Id,
            TimeZoneSidKey   = 'Europe/London',
            LocaleSidKey     = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey= 'en_US'
        );
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

        User runner = makeStandardUser();
        User member = makeStandardUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert runner;
            insert member;
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
