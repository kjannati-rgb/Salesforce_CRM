@IsTest
private class AccountMatchKeyStamper_Test {

    @IsTest
    static void stampsDomainAndNameWhenBlank() {
        Id firmRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
        Account a = new Account(Name = 'Stamper Demo Solicitors LLP', RecordTypeId = firmRt,
            Website = 'https://www.stamper-demo.co.uk/contact');
        insert a;
        Test.startTest();
        AccountMatchKeyStamper.stamp(new List<Id>{ a.Id });
        Test.stopTest();
        Account chk = [SELECT Match_Domain__c, Match_Name__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('stamper-demo.co.uk', chk.Match_Domain__c, 'domain derived from website host');
        System.assertNotEquals(null, chk.Match_Name__c, 'match name derived from account name');
        System.assert(!chk.Match_Name__c.contains('LLP'), 'legal suffix stripped from match name');
    }

    @IsTest
    static void neverOverwritesExistingKeys() {
        Id firmRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
        Account a = new Account(Name = 'Keyed Firm', RecordTypeId = firmRt,
            Website = 'https://other-site.com', Match_Domain__c = 'keyed-firm.com', Match_Name__c = 'keyed firm');
        insert a;
        Test.startTest();
        AccountMatchKeyStamper.stamp(new List<Id>{ a.Id });
        Test.stopTest();
        Account chk = [SELECT Match_Domain__c, Match_Name__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('keyed-firm.com', chk.Match_Domain__c, 'existing domain untouched');
        System.assertEquals('keyed firm', chk.Match_Name__c, 'existing name key untouched');
    }

    @IsTest
    static void freeMailWebsiteAndEmptyInputAreSafe() {
        Id firmRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
        Account a = new Account(Name = 'Freemail Firm', RecordTypeId = firmRt, Website = 'gmail.com');
        insert a;
        Test.startTest();
        AccountMatchKeyStamper.stamp(new List<Id>{ a.Id });
        AccountMatchKeyStamper.stamp(new List<Id>());
        AccountMatchKeyStamper.stamp(null);
        Test.stopTest();
        Account chk = [SELECT Match_Domain__c, Match_Name__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(null, chk.Match_Domain__c, 'free-mail host never becomes a firm key');
        System.assertNotEquals(null, chk.Match_Name__c, 'name key still stamped');
    }
}
