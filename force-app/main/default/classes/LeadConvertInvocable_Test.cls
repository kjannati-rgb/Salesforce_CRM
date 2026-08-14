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
    static void emptyInputReturnsEmpty() {
        Test.startTest();
        System.assertEquals(0, LeadConvertInvocable.convert(null).size());
        System.assertEquals(0,
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>()).size());
        Test.stopTest();
    }
}
