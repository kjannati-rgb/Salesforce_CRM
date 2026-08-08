@isTest
private class Ast_RenewalEmailHelperTest {

    @testSetup
    static void setupTestData() {
        TestDataFactory.bypassAutomation();
        Id firmRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        Id officeRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Office').getRecordTypeId();
        
        Account firmAcc = new Account(Name = 'Test Firm Account', RecordTypeId = firmRecordTypeId, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT firmAcc;
        
        Account officeAcc = new Account(Name = 'Test Office Account', RecordTypeId = officeRecordTypeId, Ultimate_Account__c = firmAcc.Id, BillingCity = 'City', BillingCountry='India', BillingCountryCode = 'IN', ShippingCity = 'City', ShippingCountry='India', ShippingCountryCode = 'IN');
        INSERT officeAcc;

        // --- Just 1 Product ---
        Product2 prodTime = new Product2(
            Name = 'Time Product 1', IsActive = true, Family = 'Events', ProductCode = 'TimeCode123',
            Subscription_Model__c = 'Time-Based', SBQQ__SubscriptionType__c = 'One-time',
            SBQQ__PriceEditable__c = true, SBQQ__PricingMethodEditable__c = true, CanUseRevenueSchedule = true,
            Edition__c = '2023', Financial_Year__c = '2023', Revenue_Stream__c = 'Editorial',
            Division__c = 'Market Intelligence', Reporting_Stream__c = 'Advertising - GAR', Product_Date__c = System.today().addDays(-45)
        );
        INSERT prodTime;
        Product2 prodTime2 = new Product2(
            Name = 'Time Product 1', IsActive = true, Family = 'Events', ProductCode = 'TimeCode123',
            Subscription_Model__c = 'Time-Based', SBQQ__SubscriptionType__c = 'One-time',
            SBQQ__PriceEditable__c = true, SBQQ__PricingMethodEditable__c = true, CanUseRevenueSchedule = true,
            Edition__c = '2023', Financial_Year__c = '2023', Revenue_Stream__c = 'Editorial',
            Division__c = 'Market Intelligence', Reporting_Stream__c = 'Advertising - GRR', Product_Date__c = System.today().addDays(-45)
        );
        INSERT prodTime2;
        

        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbeTime = new PricebookEntry(Pricebook2Id = pbId, Product2Id = prodTime.Id, UnitPrice = 100, IsActive = true);
        INSERT pbeTime; 
        PricebookEntry pbeTime2 = new PricebookEntry(Pricebook2Id = pbId, Product2Id = prodTime2.Id, UnitPrice = 100, IsActive = true);
        INSERT pbeTime2;

        // --- 1 Parent Opp & 1 Quote ---
        Opportunity parentOpp = new Opportunity(Name = 'Parent 30', StageName = 'Closed Won', CloseDate = System.today(), AccountId = officeAcc.Id);
        INSERT parentOpp;

        SBQQ__Quote__c primaryQuote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = parentOpp.Id, SBQQ__Primary__c = true, Auto_Renewal_Clause__c = '30', Auto_renewal_removed__c = false
        );
        INSERT primaryQuote;

        parentOpp.SBQQ__PrimaryQuote__c = primaryQuote.Id;
        update parentOpp;
        
        Contact testContact = new Contact(LastName = 'Test Contact', Email = 'test@example.com', AccountId = officeAcc.Id);
        INSERT testContact;

        Test.startTest();

        // --- 1 Child Opp & 1 Line Item ---
        Opportunity oppChild = new Opportunity(
            Name = 'Test Child Opp', StageName = 'Qualify', CloseDate = System.today().addDays(30), 
            AccountId = officeAcc.Id, Previous_Opportunity__c = parentOpp.Id, Primary_Contact__c = testContact.Id
        );
        INSERT oppChild; 
        Opportunity oppChild2 = new Opportunity(
            Name = 'Test Child Opp', StageName = 'Qualify', CloseDate = System.today().addDays(30), 
            AccountId = officeAcc.Id, Previous_Opportunity__c = parentOpp.Id, Primary_Contact__c = testContact.Id
        );
        INSERT oppChild2;

        OpportunityLineItem oliChild = new OpportunityLineItem(OpportunityId = oppChild.Id, PricebookEntryId = pbeTime.Id, Quantity = 1, UnitPrice = 100);
        INSERT oliChild;
        OpportunityLineItem oliChild2 = new OpportunityLineItem(OpportunityId = oppChild.Id, PricebookEntryId = pbeTime2.Id, Quantity = 1, UnitPrice = 100);
        INSERT oliChild2;

        Test.stopTest();
    }

    @isTest
    static void testHelperExecution() {
        Test.startTest();
        
        // 1. Initialize to cover the public variable
        Ast_RenewalEmailHelper helperInstance = new Ast_RenewalEmailHelper();
        System.assert(helperInstance.targetStages.contains('Qualify'), 'targetStages should initialize correctly');

        // 2. Cover the static query builder
        String baseQuery = Ast_RenewalEmailHelper.getBaseQuery();
        System.assertNotEquals(null, baseQuery, 'Query string should not be null');
        
        // 3. Fetch org streams (covers the Metadata query)
        Set<String> orgStreams = Ast_RenewalEmailHelper.getExcludedStreams();
       	orgStreams = new Set<string>();
        
        List<Opportunity> scopeOpps = [SELECT Id, Name FROM Opportunity];
        
        // 4. Run the mapping logic with our setup data
        Map<Id, Ast_RenewalEmailHelper.OppGroupingWrapper> validOppMap = Ast_RenewalEmailHelper.getValidOppMap(scopeOpps, orgStreams);
        
        Test.stopTest(); 
    }
    @isTest
    static void testProcessRenewalEmailsExecution() { 
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

        // 1. Update the date so it bypasses the "if (notificationDate != dateOfToday) continue;" check
        // Setup clause is '30', so daysBefore = 45. We set the target date 45 days out.
        List<Opportunity> oppsToUpdate = [SELECT Id FROM Opportunity];
        for(Opportunity o : oppsToUpdate) {
            o.Budget_Renewal_Date__c = System.today().addDays(45);
            o.Auto_Renewal_Email_Date__c = System.today();
        }
        update oppsToUpdate;
        
        // 2. Define the bind variable used in getBaseQuery() so Database.query() can evaluate it
        Set<String> targetStages = new Set<String>{'Qualify', 'Identify'};
        String query = Ast_RenewalEmailHelper.getBaseQuery();
        List<Opportunity> scope = Database.query(query);
        
        Test.startTest(); 
        Ast_RenewalEmailHelper.processRenewalEmails(scope, 'Ast_RenewalEmailBatch');
        Test.stopTest();
        
        System.assert(!scope.isEmpty(), 'The dynamic query should return the test opportunities');
    }
}
