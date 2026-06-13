@isTest
private class Ast_PopulateAutoRenewalDateBatchTest {

    @testSetup
    static void setupTestData() {
        TestDataFactory.bypassAutomation();
        Id firmRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        Id officeRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Office').getRecordTypeId();
        
        Account firmAcc = new Account(Name = 'Test Firm Account', RecordTypeId = firmRecordTypeId, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT firmAcc;
        
        Account officeAcc = new Account(Name = 'Test Office Account', RecordTypeId = officeRecordTypeId, Ultimate_Account__c = firmAcc.Id, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT officeAcc;

        // 1. Time-Based Product (Original)
        Product2 prodTime = new Product2(
            Name = 'Time Product', IsActive = true, Family = 'Events', ProductCode = 'TimeCode123',
            Subscription_Model__c = 'Time-Based', SBQQ__SubscriptionType__c = 'One-time',
            SBQQ__PriceEditable__c = true, SBQQ__PricingMethodEditable__c = true, CanUseRevenueSchedule = true,
            Edition__c = '2023', Financial_Year__c = '2023', Revenue_Stream__c = 'Editorial',
            Division__c = 'Market Intelligence', Reporting_Stream__c = 'Advertising - GAR', 
            Product_Date__c = System.today().addDays(-45) 
        );
        
        // 2. Edition-Based Product (Exact clone of above, just changed the Model and added Product_Date__c)
        Product2 prodEdition = new Product2(
            Name = 'Edition Product', IsActive = true, Family = 'Events', ProductCode = 'EdCode123',
            Subscription_Model__c = 'Edition-Based', SBQQ__SubscriptionType__c = 'One-time',
            SBQQ__PriceEditable__c = true, SBQQ__PricingMethodEditable__c = true, CanUseRevenueSchedule = true,
            Edition__c = '2023', Financial_Year__c = '2023', Revenue_Stream__c = 'Editorial',
            Division__c = 'Market Intelligence', Reporting_Stream__c = 'Advertising - GAR',
            Product_Date__c = System.today().addDays(-45) 
        );
        INSERT new List<Product2>{prodTime, prodEdition};

        PricebookEntry pbeTime = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prodTime.Id, UnitPrice = 100, IsActive = true);
        PricebookEntry pbeEdition = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prodEdition.Id, UnitPrice = 100, IsActive = true);
        INSERT new List<PricebookEntry>{pbeTime, pbeEdition};

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

        // 3. Time-Based Opp
        Opportunity oppTime = new Opportunity(
            Name = 'Test Time Success', 
            StageName = 'Qualify', 
            CloseDate = System.today().addDays(30), 
            AccountId = officeAcc.Id, 
            Previous_Opportunity__c = parentOpp.Id, 
            Budget_Renewal_Date__c = System.today().addDays(45),
            Primary_Contact__c = testContact.Id
        );
        
        // 4. Edition-Based Opp
        Opportunity oppEdition = new Opportunity(
            Name = 'Test Edition Success', 
            StageName = 'Qualify', 
            CloseDate = System.today().addDays(30), 
            AccountId = officeAcc.Id, 
            Previous_Opportunity__c = parentOpp.Id, 
            Primary_Contact__c = testContact.Id
        );
        INSERT new List<Opportunity>{oppTime, oppEdition};

        // 5. Attach OLIs
        OpportunityLineItem oli1 = new OpportunityLineItem(OpportunityId = oppTime.Id, PricebookEntryId = pbeTime.Id, Quantity = 1, UnitPrice = 100);
        OpportunityLineItem oli2 = new OpportunityLineItem(OpportunityId = oppEdition.Id, PricebookEntryId = pbeEdition.Id, Quantity = 1, UnitPrice = 100);
        INSERT new List<OpportunityLineItem>{oli1, oli2};

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
 
        

        Test.stopTest();
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        Ast_PopulateAutoRenewalDateBatch batch = new Ast_PopulateAutoRenewalDateBatch();
        Database.executeBatch(batch);
        Test.stopTest();
    }
}
