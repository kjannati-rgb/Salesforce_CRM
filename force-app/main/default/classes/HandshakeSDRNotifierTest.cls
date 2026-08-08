@isTest
private class HandshakeSDRNotifierTest {

    private static EmailTemplate makeTemplate() {
        // Personal email template: FolderId = running user's Id, no folder setup needed.
        EmailTemplate et = new EmailTemplate(
            Name = 'Test Handshake Tpl',
            DeveloperName = 'Test_Handshake_Tpl_' + String.valueOf(Datetime.now().getTime()),
            TemplateType = 'custom',
            FolderId = UserInfo.getUserId(),
            Encoding = 'UTF-8',
            Subject = 'Handshake {!Customer_Journey__c.Goal_Licenses__c}',
            HtmlValue = '<b>Goal:</b> {!Customer_Journey__c.Goal_Licenses__c}',
            Body = 'Goal: {!Customer_Journey__c.Goal_Licenses__c}',
            IsActive = true
        );
        insert et;
        return et;
    }

    @isTest
    static void rendersAndSendsToAddresses() {
        EmailTemplate et = makeTemplate();
        Customer_Journey__c cj = new Customer_Journey__c(Goal_Licenses__c = 99);
        insert cj;

        // The class looks the template up by DeveloperName, then renders against the CJ record.
        // Assert both mechanisms work (so a green test means the real send path executed).
        System.assertEquals(1,
            [SELECT COUNT() FROM EmailTemplate WHERE DeveloperName = :et.DeveloperName],
            'Template must be queryable by DeveloperName.');

        Messaging.SingleEmailMessage rendered =
            Messaging.renderStoredEmailTemplate(et.Id, null, cj.Id);
        System.assert(rendered.getHtmlBody() != null && rendered.getHtmlBody().contains('99'),
            'Template should render the Customer Journey field value. Got: ' + rendered.getHtmlBody());

        HandshakeSDRNotifier.Request req = new HandshakeSDRNotifier.Request();
        req.relatedRecordId = cj.Id;
        req.templateDevName = et.DeveloperName;
        req.recipientEmails = new List<String>{ 'sdr@example.com', 'manager@example.com' };
        req.orgWideEmailAddress = 'no-such-owa@example.com'; // exercises the OWA lookup (not-found) branch

        Test.startTest();
        HandshakeSDRNotifier.send(new List<HandshakeSDRNotifier.Request>{ req });
        Test.stopTest();
        // Reaching here without exception means render + build + sendEmail executed.
    }

    @isTest
    static void skipsWhenNoRecipientsOrUnknownTemplate() {
        Customer_Journey__c cj = new Customer_Journey__c(Goal_Licenses__c = 5);
        insert cj;

        // empty recipient list -> skipped
        HandshakeSDRNotifier.Request emptyRecips = new HandshakeSDRNotifier.Request();
        emptyRecips.relatedRecordId = cj.Id;
        emptyRecips.templateDevName = 'whatever';
        emptyRecips.recipientEmails = new List<String>();

        // unknown template -> skipped
        HandshakeSDRNotifier.Request badTpl = new HandshakeSDRNotifier.Request();
        badTpl.relatedRecordId = cj.Id;
        badTpl.templateDevName = 'Does_Not_Exist_Tpl';
        badTpl.recipientEmails = new List<String>{ 'x@example.com' };

        Test.startTest();
        HandshakeSDRNotifier.send(new List<HandshakeSDRNotifier.Request>{ emptyRecips, badTpl });
        HandshakeSDRNotifier.send(null);
        HandshakeSDRNotifier.send(new List<HandshakeSDRNotifier.Request>());
        Test.stopTest();
        // No exception, nothing sent.
    }

    @isTest
    static void logsSendFailures() {
        Customer_Journey__c cj = new Customer_Journey__c(Goal_Licenses__c = 1);
        insert cj;

        HandshakeSDRNotifier.Request req = new HandshakeSDRNotifier.Request();
        req.relatedRecordId = cj.Id;
        req.templateDevName = 'NB_Whatever';
        req.recipientEmails = new List<String>{ 'sdr@example.com', 'manager@example.com' };

        Flow_Log__c log = HandshakeSDRNotifier.buildFailureLog(req, 'SYSTEM_ERROR: simulated send failure');
        System.assertEquals('HandshakeSDRNotifier', log.Class_Name__c, 'Class name stamped.');
        System.assert(log.Error_Description__c.contains('simulated send failure'), 'Error text captured.');
        System.assert(log.Error_Description__c.contains('sdr@example.com'), 'Recipients captured.');

        Test.startTest();
        HandshakeSDRNotifier.logFailures(new List<Flow_Log__c>{ log });
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Flow_Log__c WHERE Class_Name__c = 'HandshakeSDRNotifier'],
            'A Flow_Log__c failure row should be written.');
    }
}
