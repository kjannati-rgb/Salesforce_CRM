@isTest
private class ContactRoleCheckRecomputeTest {

    @testSetup
    static void setup() {
        // Disable kill-switch-respecting automation so the test is focused on the batch
        // (the batch computes the flags itself; the before-save flow is not needed here).
        insert new Application_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true,
            Disable_Validation_Rules__c = true
        );

        Id nb = [SELECT Id FROM RecordType WHERE SobjectType='Opportunity' AND DeveloperName='New_Business' LIMIT 1].Id;
        Date cd = Date.today().addMonths(2);

        Account accOk = new Account(Name='CRC T Acc OK', BillingStreet='1 St', BillingCity='London', BillingCountry='United Kingdom');
        Account accNo = new Account(Name='CRC T Acc No');
        insert new List<Account>{ accOk, accNo };

        Contact cOk = new Contact(FirstName='A', LastName='CRC Ok', AccountId=accOk.Id,
            Email='a@b.com', Title='CFO', MailingStreet='1 St', MailingCity='London');
        Contact cNoEmail = new Contact(FirstName='B', LastName='CRC NoEmail', AccountId=accOk.Id,
            Title='CFO', MailingStreet='1 St', MailingCity='London'); // missing Email
        insert new List<Contact>{ cOk, cNoEmail };

        Opportunity oComplete   = new Opportunity(Name='CRC Complete',   AccountId=accOk.Id, StageName='Identify', Probability=10, CloseDate=cd, RecordTypeId=nb);
        Opportunity oNoRole     = new Opportunity(Name='CRC NoRole',     AccountId=accOk.Id, StageName='Identify', Probability=10, CloseDate=cd, RecordTypeId=nb);
        Opportunity oIncContact = new Opportunity(Name='CRC IncContact', AccountId=accOk.Id, StageName='Identify', Probability=10, CloseDate=cd, RecordTypeId=nb);
        Opportunity oNoBill     = new Opportunity(Name='CRC NoBill',     AccountId=accNo.Id, StageName='Identify', Probability=10, CloseDate=cd, RecordTypeId=nb);
        insert new List<Opportunity>{ oComplete, oNoRole, oIncContact, oNoBill };

        insert new List<OpportunityContactRole>{
            new OpportunityContactRole(OpportunityId=oComplete.Id,   ContactId=cOk.Id,      IsPrimary=true, Role='Decision Maker'),
            new OpportunityContactRole(OpportunityId=oIncContact.Id, ContactId=cNoEmail.Id, IsPrimary=true, Role='Decision Maker'),
            new OpportunityContactRole(OpportunityId=oNoBill.Id,     ContactId=cOk.Id,      IsPrimary=true, Role='Decision Maker')
        };
    }

    @isTest
    static void testRecomputeAllScenarios() {
        Test.startTest();
        Database.executeBatch(new ContactRoleCheckRecompute('IsClosed = false AND Name LIKE \'CRC %\''), 50);
        Test.stopTest();

        Map<String, Opportunity> byName = new Map<String, Opportunity>();
        for (Opportunity o : [
            SELECT Name, Has_Contact_Role__c, Has_Complete_Contact_Role__c
            FROM Opportunity WHERE Name LIKE 'CRC %'
        ]) {
            byName.put(o.Name, o);
        }

        System.assertEquals(true,  byName.get('CRC Complete').Has_Contact_Role__c,          'Complete: has role');
        System.assertEquals(true,  byName.get('CRC Complete').Has_Complete_Contact_Role__c, 'Complete: complete');

        System.assertEquals(false, byName.get('CRC NoRole').Has_Contact_Role__c,            'NoRole: no role');
        System.assertEquals(false, byName.get('CRC NoRole').Has_Complete_Contact_Role__c,   'NoRole: not complete');

        System.assertEquals(true,  byName.get('CRC IncContact').Has_Contact_Role__c,          'IncContact: has role');
        System.assertEquals(false, byName.get('CRC IncContact').Has_Complete_Contact_Role__c, 'IncContact: not complete (no email)');

        System.assertEquals(true,  byName.get('CRC NoBill').Has_Contact_Role__c,          'NoBill: has role');
        System.assertEquals(false, byName.get('CRC NoBill').Has_Complete_Contact_Role__c, 'NoBill: not complete (account billing)');
    }

    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        Database.executeBatch(new ContactRoleCheckRecompute(), 200);
        Test.stopTest();
        // Smoke: default constructor + start()/execute()/finish() run without error.
        System.assert([SELECT COUNT() FROM Opportunity WHERE Name LIKE 'CRC %'] == 4, 'test data present');
    }
}
