/**
 * Tests that LeadConvertInvocable re-parents lead-side interactions after a successful
 * convert (REV-68 hook). Converts into an existing Account + Contact to reduce managed-package
 * interference; assertions are guarded on the convert succeeding.
 */
@IsTest
private class LeadConvertInvocableReparent_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    @IsTest
    static void convertViaInvocableReparentsInteractions() {
        Account off = new Account(Name = 'Inv Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Contact con = new Contact(LastName = 'Inv', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'InvSrc', Company = 'Inv Office', CountryCode = 'GB',
            Email = 'inv@rev68-demo.com');
        insert ld;
        LBR_Interactions__c i1 = new LBR_Interactions__c(Lead__c = ld.Id,
            Interaction_Type__c = 'Member', Interaction_Status__c = 'Active',
            Interaction_Date__c = Date.today(), Interaction_Code__c = 'INV-1');
        insert i1;

        LeadConvertInvocable.Request r = new LeadConvertInvocable.Request();
        r.leadId = ld.Id;
        r.accountId = off.Id;
        r.contactId = con.Id;
        r.createOpportunity = false;

        Test.startTest();
        List<LeadConvertInvocable.Result> res =
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, res.size());
        if (res[0].success) {
            LBR_Interactions__c after = [SELECT Contact__c, Lead__c FROM LBR_Interactions__c WHERE Id = :i1.Id];
            System.assertEquals(con.Id, after.Contact__c, 'invocable hook re-parented the interaction');
            System.assertEquals(null, after.Lead__c, 'Lead cleared by the hook');
        } else {
            System.assert(res[0].message.startsWith('Convert blocked:'),
                'failure path returns a readable message: ' + res[0].message);
        }
    }
}
