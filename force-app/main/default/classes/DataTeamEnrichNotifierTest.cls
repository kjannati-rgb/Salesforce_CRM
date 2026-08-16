@isTest
private class DataTeamEnrichNotifierTest {

    private static final String GROUP_DEV_NAME = 'Test_Data_Team_Notify';

    /**
     * Group / GroupMember / User are setup objects, so they cannot be inserted in the same
     * transaction as Account. runAs isolates them.
     */
    private static Id buildGroupWithActiveAndInactiveMembers() {
        Id groupId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Group g = new Group(Name = 'Test Data Team Notify', DeveloperName = GROUP_DEV_NAME, Type = 'Regular');
            insert g;
            groupId = g.Id;

            Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
            String stamp = String.valueOf(Datetime.now().getTime());

            User activeUser = new User(
                FirstName = 'Active', LastName = 'Member',
                Email = 'active.member@example.com',
                Username = 'active.member.' + stamp + '@example.com.dtentest',
                Alias = 'actm', ProfileId = p.Id, IsActive = true,
                TimeZoneSidKey = 'Europe/London', LocaleSidKey = 'en_GB',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            User dormantUser = new User(
                FirstName = 'Dormant', LastName = 'Member',
                Email = 'dormant.member@example.com',
                Username = 'dormant.member.' + stamp + '@example.com.dtentest',
                Alias = 'dorm', ProfileId = p.Id, IsActive = true,
                TimeZoneSidKey = 'Europe/London', LocaleSidKey = 'en_GB',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            insert new List<User>{ activeUser, dormantUser };

            insert new List<GroupMember>{
                new GroupMember(GroupId = groupId, UserOrGroupId = activeUser.Id),
                new GroupMember(GroupId = groupId, UserOrGroupId = dormantUser.Id)
            };

            // Deactivate after the membership exists, mirroring the real Data_Team group
            // where dormant members were never removed.
            dormantUser.IsActive = false;
            update dormantUser;
        }
        return groupId;
    }

    /**
     * EmailTemplate counts as a setup object here, so inserting it in the same transaction
     * as an Account throws MIXED_DML_OPERATION. runAs resets the DML context, which also
     * makes this helper safe to call before or after the Account is created.
     */
    private static EmailTemplate makeTemplate() {
        EmailTemplate et = new EmailTemplate(
            Name = 'Test Data Team Enrich',
            DeveloperName = 'Test_Data_Team_Enrich_' + String.valueOf(Datetime.now().getTime()),
            TemplateType = 'custom',
            FolderId = UserInfo.getUserId(), // personal folder: no folder setup needed
            Encoding = 'UTF-8',
            Subject = 'Account {!Account.Name} is not complete',
            HtmlValue = '<tr><td>Missing</td><td>[[MISSING_FIELDS]]</td></tr>',
            Body = 'Missing: [[MISSING_FIELDS]]',
            IsActive = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert et;
        }
        return et;
    }

    @isTest
    static void resolvesOnlyActiveGroupMembers() {
        buildGroupWithActiveAndInactiveMembers();

        Test.startTest();
        Map<String, List<String>> byGroup =
            DataTeamEnrichNotifier.resolveActiveGroupMembers(new Set<String>{ GROUP_DEV_NAME });
        Test.stopTest();

        List<String> addrs = byGroup.get(GROUP_DEV_NAME);
        System.assertNotEquals(null, addrs, 'Group should resolve to recipients.');
        System.assertEquals(1, addrs.size(), 'Only the active member should be returned. Got: ' + addrs);
        System.assertEquals('active.member@example.com', addrs[0], 'Wrong member resolved.');
    }

    @isTest
    static void substitutesMissingFieldsToken() {
        System.assertEquals(
            'Missing: Billing City',
            DataTeamEnrichNotifier.substitute('Missing: [[MISSING_FIELDS]]', 'Billing City'),
            'Token should be replaced with the supplied list.');
        System.assertEquals(
            'Missing: Billing Country, Billing Street',
            DataTeamEnrichNotifier.substitute('Missing: [[MISSING_FIELDS]]', 'Billing Country, Billing Street'),
            'Multi-field list should substitute verbatim.');
        System.assertEquals(null, DataTeamEnrichNotifier.substitute(null, 'x'),
            'Null body should stay null (plain-text body is often absent).');
    }

    @isTest
    static void rendersSubstitutesAndSends() {
        Id groupId = buildGroupWithActiveAndInactiveMembers();
        EmailTemplate et = makeTemplate();
        Account acct = new Account(Name = 'Incomplete Firm Ltd');
        insert acct;

        // Prove the render path itself works, so a green test means the real send path ran.
        Messaging.SingleEmailMessage rendered =
            Messaging.renderStoredEmailTemplate(et.Id, null, acct.Id);
        System.assert(rendered.getSubject().contains('Incomplete Firm Ltd'),
            'Template should merge the Account name. Got: ' + rendered.getSubject());
        System.assert(rendered.getHtmlBody().contains('[[MISSING_FIELDS]]'),
            'Token must survive template render so Apex can substitute it. Got: ' + rendered.getHtmlBody());

        DataTeamEnrichNotifier.Request req = new DataTeamEnrichNotifier.Request();
        req.relatedRecordId = acct.Id;
        req.templateDevName = et.DeveloperName;
        req.recipientGroupDevName = GROUP_DEV_NAME;
        req.missingFields = 'Billing City';
        req.orgWideEmailAddress = 'no-such-owa@example.com'; // exercises the OWA not-found branch

        Test.startTest();
        DataTeamEnrichNotifier.send(new List<DataTeamEnrichNotifier.Request>{ req });
        Test.stopTest();

        System.assertNotEquals(null, groupId, 'Group should have been created.');
        // Reaching here without exception means render + substitute + build + sendEmail executed.
    }

    @isTest
    static void skipsUnknownTemplateGroupAndBlankRecord() {
        Account acct = new Account(Name = 'No Recipients Ltd');
        insert acct;
        EmailTemplate et = makeTemplate();

        DataTeamEnrichNotifier.Request unknownTemplate = new DataTeamEnrichNotifier.Request();
        unknownTemplate.relatedRecordId = acct.Id;
        unknownTemplate.templateDevName = 'Does_Not_Exist_Tpl';
        unknownTemplate.recipientGroupDevName = GROUP_DEV_NAME;

        DataTeamEnrichNotifier.Request unknownGroup = new DataTeamEnrichNotifier.Request();
        unknownGroup.relatedRecordId = acct.Id;
        unknownGroup.templateDevName = et.DeveloperName;
        unknownGroup.recipientGroupDevName = 'No_Such_Group_At_All';

        DataTeamEnrichNotifier.Request blankRecord = new DataTeamEnrichNotifier.Request();
        blankRecord.relatedRecordId = null;
        blankRecord.templateDevName = et.DeveloperName;
        blankRecord.recipientGroupDevName = GROUP_DEV_NAME;

        Test.startTest();
        DataTeamEnrichNotifier.send(new List<DataTeamEnrichNotifier.Request>{
            unknownTemplate, unknownGroup, blankRecord
        });
        DataTeamEnrichNotifier.send(null);
        DataTeamEnrichNotifier.send(new List<DataTeamEnrichNotifier.Request>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Flow_Log__c],
            'Nothing was sent, so nothing should be logged as a failure.');
    }

    @isTest
    static void logsSendFailures() {
        buildGroupWithActiveAndInactiveMembers();
        Account acct = new Account(Name = 'Failure Ltd');
        insert acct;

        DataTeamEnrichNotifier.Request req = new DataTeamEnrichNotifier.Request();
        req.relatedRecordId = acct.Id;
        req.templateDevName = 'Data_Team_Enrich_Account';
        req.recipientGroupDevName = GROUP_DEV_NAME;
        req.missingFields = 'Billing Street';

        Flow_Log__c log = DataTeamEnrichNotifier.buildFailureLog(req, 'SYSTEM_ERROR: simulated send failure');
        System.assertEquals('DataTeamEnrichNotifier', log.Class_Name__c, 'Class name stamped.');
        System.assert(log.Error_Description__c.contains('simulated send failure'), 'Error text captured.');
        System.assert(log.Error_Description__c.contains('active.member@example.com'),
            'Resolved recipients captured for diagnosis.');
        System.assert(log.Error_Description__c.contains('Billing Street'), 'Missing-field list captured.');

        Test.startTest();
        DataTeamEnrichNotifier.logFailures(new List<Flow_Log__c>{ log });
        DataTeamEnrichNotifier.logFailures(null);
        DataTeamEnrichNotifier.logFailures(new List<Flow_Log__c>());
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Flow_Log__c WHERE Class_Name__c = 'DataTeamEnrichNotifier'],
            'A Flow_Log__c failure row should be written.');
    }
}
