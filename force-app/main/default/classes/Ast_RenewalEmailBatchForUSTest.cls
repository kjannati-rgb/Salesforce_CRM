@isTest
private class Ast_RenewalEmailBatchForUSTest { 
    @testSetup
    static void setupTestData() {
        TestDataFactory.bypassAutomation();
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User ukTestUser = new User(
            FirstName = 'UK',
            LastName = 'BatchTester',
            Email = 'ukbatchtester@example.com',
            Username = 'ukbatchtester' + DateTime.now().getTime() + '@test.com',
            Alias = 'ukbt',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id,
            LBR_Legal_Entity__c = 'ALM Global, LLC' 
        );
        INSERT ukTestUser;
        
        Id firmRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        Id officeRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Office').getRecordTypeId();
        
        Account firmAcc = new Account(Name = 'Test Firm Account', RecordTypeId = firmRecordTypeId, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT firmAcc;
        
        Account officeAcc = new Account(Name = 'Test Office Account', RecordTypeId = officeRecordTypeId, Ultimate_Account__c = firmAcc.Id, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT officeAcc;

        Product2 prodTime = new Product2(
            Name = 'Time Product', IsActive = true, Family = 'Events', ProductCode = 'TimeCode123',
            Subscription_Model__c = 'Time-Based', SBQQ__SubscriptionType__c = 'One-time',
            SBQQ__PriceEditable__c = true, SBQQ__PricingMethodEditable__c = true, CanUseRevenueSchedule = true,
            Edition__c = '2023', Financial_Year__c = '2023', Revenue_Stream__c = 'Editorial',
            Division__c = 'Market Intelligence', Reporting_Stream__c = 'Advertising - GAR',
            Product_Date__c = System.today().addDays(-45) 
        );
        INSERT prodTime;

        PricebookEntry pbeTime = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prodTime.Id, UnitPrice = 100, IsActive = true);
        INSERT pbeTime;

        Opportunity parentOpp = new Opportunity(Name = 'Parent 30', StageName = 'Closed Won', CloseDate = System.today(), AccountId = officeAcc.Id);
        INSERT parentOpp;

        SBQQ__Quote__c primaryQuote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = parentOpp.Id, SBQQ__Primary__c = true, Auto_Renewal_Clause__c = '30', Auto_renewal_removed__c = false
        );
        INSERT primaryQuote;

        parentOpp.SBQQ__PrimaryQuote__c = primaryQuote.Id;
        update parentOpp;
        
        Contact testContact = new Contact(
            LastName = 'Test Contact', 
            Email = 'test@example.com', 
            AccountId = officeAcc.Id
        );
        INSERT testContact;

        Test.startTest();
        Opportunity oppTime = new Opportunity();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity oppTimeRecord = new Opportunity(
                Name = 'Test Time Success', 
                StageName = 'Qualify', 
                CloseDate = System.today().addDays(30), 
                AccountId = officeAcc.Id, 
                Previous_Opportunity__c = parentOpp.Id, 
                Budget_Renewal_Date__c = System.today().addDays(45),
                Primary_Contact__c = testContact.Id, 
                Auto_Renewal_Email_Date__c = System.today(),
                OwnerId = ukTestUser.Id
            );
            INSERT oppTimeRecord;
            oppTime = oppTimeRecord;
        } 
        

        OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = oppTime.Id, PricebookEntryId = pbeTime.Id, Quantity = 1, UnitPrice = 100);
        INSERT oli;

        EmailTemplate validEmailTemplate;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            validEmailTemplate = new EmailTemplate(
                isActive = true,
                Name = 'Test Renewal Template',
                DeveloperName = 'Test_Renewal_Template_123',
                TemplateType = 'custom', 
                FolderId = UserInfo.getUserId(),
                Subject = 'Test Subject',
                HtmlValue = '<html><body>Test Body {PRODUCT_TABLE_PLACEHOLDER} {AutoRenewalPeriod} {InvoiceContactFromPreviousOpp}</body></html>'
            );
            INSERT validEmailTemplate;
        }
 
        Renewal_Email_Template_Configuration__c config = new Renewal_Email_Template_Configuration__c( 
            Reporting_Stream__c = 'Advertising - GAR', 
            Email_Template_Id__c = validEmailTemplate.Id,
            Default__c = false
        );
        INSERT config;
        
        Renewal_Email_Template_Configuration__c config2 = new Renewal_Email_Template_Configuration__c(  
            Email_Template_Id__c = validEmailTemplate.Id,
            Default__c = true
        );
        INSERT config2;

        Test.stopTest(); 
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        Ast_RenewalEmailBatchForUS batch = new Ast_RenewalEmailBatchForUS();
        Database.executeBatch(batch);
        Test.stopTest();
    }
}
