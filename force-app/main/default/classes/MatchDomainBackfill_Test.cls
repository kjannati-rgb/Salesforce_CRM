@IsTest
private class MatchDomainBackfill_Test {

    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @IsTest
    static void backfills_fromWebsiteAndContacts() {
        // A: Firm with a website signal
        Account a = new Account(Name = 'Website Firm', RecordTypeId = FIRM_RT,
            Website = 'https://www.websitefirm.com/contact');
        // B: Office with no field signal -> resolved from its contacts' email domains
        //    (contacts must sit on Office record-type accounts in this org)
        Account b = new Account(Name = 'Contact Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert new List<Account>{ a, b };
        insert new List<Contact>{
            new Contact(LastName = 'One', Email = 'p1@contactfirm.com', AccountId = b.Id),
            new Contact(LastName = 'Two', Email = 'p2@contactfirm.com', AccountId = b.Id),
            new Contact(LastName = 'Free', Email = 'someone@gmail.com', AccountId = b.Id)   // free-mail ignored
        };

        Test.startTest();
        Database.executeBatch(new MatchDomainBackfill(), 200);
        Test.stopTest();

        Map<Id, Account> after = new Map<Id, Account>([
            SELECT Id, Match_Domain__c, Match_Name__c FROM Account WHERE Id IN :new List<Id>{ a.Id, b.Id }
        ]);
        System.assertEquals('websitefirm.com', after.get(a.Id).Match_Domain__c, 'from website host');
        System.assertEquals('contactfirm.com', after.get(b.Id).Match_Domain__c, 'modal contact domain, free-mail ignored');
        System.assertEquals('website firm', after.get(a.Id).Match_Name__c, 'normalised name key');
        System.assertEquals('contact office', after.get(b.Id).Match_Name__c);
    }

    @IsTest
    static void normalizeFirmName_stripsSuffixesAndPunctuation() {
        System.assertEquals('dentons', MatchDomainBackfill.normalizeFirmName('Dentons LLP'));
        System.assertEquals('dentons', MatchDomainBackfill.normalizeFirmName('Dentons'));
        System.assertEquals('marsh mclennan companies',
            MatchDomainBackfill.normalizeFirmName('The Marsh & McLennan Companies, Inc.'));
        System.assertEquals(null, MatchDomainBackfill.normalizeFirmName('  '));
    }

    @IsTest
    static void fromFields_prefersGrooveThenWebsite() {
        Account g = new Account(DaScoopComposer__Domain_1__c = 'groove.com', Website = 'https://www.other.com');
        System.assertEquals('groove.com', MatchDomainBackfill.fromFields(g));
        Account w = new Account(Website = 'https://www.weby.com');
        System.assertEquals('weby.com', MatchDomainBackfill.fromFields(w));
        Account n = new Account(Name = 'No signal');
        System.assertEquals(null, MatchDomainBackfill.fromFields(n));
    }
}
