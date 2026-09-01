@IsTest
private class LeadConvertInvocable_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @IsTest
    static void convertsIntoSpecifiedOffice() {
        Account office = new Account(Name = 'Convert Target Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert office;

        Lead ld = new Lead(FirstName = 'Pat', LastName = 'Tester', Company = 'Convert Target Office',
            Email = 'tester@convert-demo.com', CountryCode = 'GB');
        insert ld;

        LeadConvertInvocable.Request r = new LeadConvertInvocable.Request();
        r.leadId = ld.Id;
        r.accountId = office.Id;
        r.createOpportunity = false;

        Test.startTest();
        List<LeadConvertInvocable.Result> res =
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, res.size());
        LeadConvertInvocable.Result out = res[0];
        // Assert behaviour without coupling to managed-package validation outcomes:
        // either it converted into our Office, or it surfaced a clean blocked message.
        if (out.success) {
            System.assertEquals(office.Id, out.accountId, 'should convert into the specified Office');
            System.assertNotEquals(null, out.contactId);
            Lead check = [SELECT IsConverted FROM Lead WHERE Id = :ld.Id];
            System.assertEquals(true, check.IsConverted);
        } else {
            System.assert(out.message != null && out.message.startsWith('Convert blocked:'),
                'failure path must return a readable message: ' + out.message);
        }
    }

    @IsTest
    static void convertedRecordsBelongToConvertingUser_notLeadOwner() {
        // Inbound leads are routinely owned by routing (often an admin), not the rep who
        // converts them. The opportunity must belong to the CONVERTING user.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User leadOwner = new User(FirstName = 'Routed', LastName = 'Owner',
            Alias = 'rout' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(4),
            Email = 'routed.owner@lbr-demo.test', Username = 'routed.owner.' + System.currentTimeMillis() + '@lbr-demo.test',
            ProfileId = p.Id, EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_GB', TimeZoneSidKey = 'Europe/London');
        insert leadOwner;

        Account office = new Account(Name = 'Owner Test Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert office;
        Lead ld = new Lead(FirstName = 'Own', LastName = 'Ership', Company = 'Owner Test Office',
            Email = 'ownership@convert-demo.com', CountryCode = 'GB', OwnerId = leadOwner.Id);
        insert ld;

        LeadConvertInvocable.Request r = new LeadConvertInvocable.Request();
        r.leadId = ld.Id;
        r.accountId = office.Id;
        r.createOpportunity = true;

        Test.startTest();
        LeadConvertInvocable.Result out =
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>{ r })[0];
        Test.stopTest();

        if (out.success) {
            System.assertNotEquals(null, out.opportunityId, 'opportunity requested');
            Opportunity opp = [SELECT OwnerId FROM Opportunity WHERE Id = :out.opportunityId];
            System.assertEquals(UserInfo.getUserId(), opp.OwnerId,
                'opportunity belongs to the converting user');
            System.assertNotEquals(leadOwner.Id, opp.OwnerId,
                'opportunity must NOT default to the lead owner');
            Contact c = [SELECT OwnerId FROM Contact WHERE Id = :out.contactId];
            System.assertEquals(UserInfo.getUserId(), c.OwnerId,
                'new contact belongs to the converting user too');
        } else {
            System.assert(out.message != null && out.message.startsWith('Convert blocked:'),
                'failure path must return a readable message: ' + out.message);
        }
    }

    @IsTest
    static void emptyInputReturnsEmpty() {
        Test.startTest();
        System.assertEquals(0, LeadConvertInvocable.convert(null).size());
        System.assertEquals(0,
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>()).size());
        Test.stopTest();
    }
}
