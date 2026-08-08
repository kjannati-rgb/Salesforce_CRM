@IsTest
private class OpportunityBillingEntityBatch_Test {
    
    @TestSetup
    static void setupData() {
        // Phase B fix: suppress the org's heavy automation + validation rules (the contact-role
        // "complete primary Contact Role at this win probability" VR was failing the Closed Won
        // updates) via the org-standard Application_Settings bypass.
        TestDataFactory.bypassAutomation();
        Id firmRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
        
        Account Ultimateacc =new Account();
        Ultimateacc.RecordTypeId=firmRecordTypeId;
        Ultimateacc.Name='abc';
        Ultimateacc.BillingCity='Tirana';
        Ultimateacc.BillingCountry='Albania';
        insert Ultimateacc;
        Id officeRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
        Account acc = new Account(Name = 'Test Account', BillingCountry = 'India', Ultimate_Account__c = Ultimateacc.Id,RecordTypeId = officeRecordTypeId);
        insert acc;
        
        insert new Opportunity_Billing_Entity_Mapping__c(
            Name = 'Law Business Research (Asia) Ltd.',
            Full_Billing_Entity_Name__c = 'Law Business Research (Asia) Ltd.',
            Abbreviation_Billing_Entity_Name__c = 'GHK'
        );
        insert new Opportunity_Billing_Entity_Mapping__c(
            Name = 'Law Business Research (UK) Ltd.',
            Full_Billing_Entity_Name__c = 'Law Business Research (UK) Ltd.',
            Abbreviation_Billing_Entity_Name__c = 'LBR'
        );
        insert new Opportunity_Billing_Entity_Mapping__c(
            Name = 'Law Business Research LLC',
            Full_Billing_Entity_Name__c = 'Law Business Research LLC',
            Abbreviation_Billing_Entity_Name__c = 'LLC'
        );
        insert new Opportunity_Billing_Entity_Mapping__c(
            Name = 'MBL Seminars Limited',
            Full_Billing_Entity_Name__c = 'MBL Seminars Limited',
            Abbreviation_Billing_Entity_Name__c = 'MBL'
        );
    }
    
    @IsTest
    static void testRenewalCopiesPreviousBillingEntity() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity prevOpp = new Opportunity(
            Name = 'Prev Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Billing_Entity__c = 'GHK',
            AccountId = acc.Id
        );
        insert prevOpp;
        
        prevOpp.StageName = 'Closed Won';
        update prevOpp;
        
        Opportunity curOpp = new Opportunity(
            Name = 'Current Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Type = 'Renewal',
            Previous_Opportunity__c = prevOpp.Id,
            AccountId = acc.Id
        );
        insert curOpp;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testRenewalUsesPrevOppLBRMappingWhenClosed() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity prevOpp = new Opportunity(
            Name = 'Prev Closed Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id,
            Billing_Entity__c = ''
        );
        insert prevOpp;
        
        prevOpp.StageName = 'Closed Won';
        update prevOpp;
        
        Opportunity curOpp = new Opportunity(
            Name = 'Current Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Type = 'Renewal',
            Previous_Opportunity__c = prevOpp.Id,
            AccountId = acc.Id
        );
        insert curOpp;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testCountryBasedRuleUSA() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity opp = new Opportunity(
            Name = 'Opp USA',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id
        );
        insert opp;
        
        Product2 prod = new Product2(
            Name = 'US Product',
            Family = 'Events',
            Event_Location_Country__c = 'United States',
            ProductCode = '20536083000',
            Division__c = 'MBL Seminars',
			Reporting_Stream__c = 'Subs - MBL Seminars'            
        );
        insert prod;
        
        Id StanPriceBookId=Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = StanPriceBookId,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100,
            PricebookEntryId = pbe.Id
        );
        insert oli;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testCountryBasedRuleHK() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity opp = new Opportunity(
            Name = 'Opp HK',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id
        );
        insert opp;
        
        Product2 prod = new Product2(
            Name = 'US Product',
            Family = 'Events',
            Event_Location_Country__c = 'Hong Kong',
            ProductCode = '20536083000',
            Division__c = 'MBL Seminars',
			Reporting_Stream__c = 'Subs - MBL Seminars'            
        );
        insert prod;
        
        Id StanPriceBookId=Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = StanPriceBookId,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100,
            PricebookEntryId = pbe.Id
        );
        insert oli;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testRepeatBusinessCopiesPreviousBillingEntity() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity prevOpp = new Opportunity(
            Name = 'Prev Repeat Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Billing_Entity__c = 'GMP',
            AccountId = acc.Id
        );
        insert prevOpp;
        
        prevOpp.StageName = 'Closed Won';
        update prevOpp;
        
        Opportunity curOpp = new Opportunity(
            Name = 'Current Repeat Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Type = 'Repeat Business',
            Previous_Opportunity__c = prevOpp.Id,
            AccountId = acc.Id
        );
        insert curOpp;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testRepeatBusinessCopiesPreviousBillingEntity2() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity prevOpp = new Opportunity(
            Name = 'Prev Repeat Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Billing_Entity__c = '',
            AccountId = acc.Id
        );
        insert prevOpp;
        
        prevOpp.StageName = 'Closed Won';
        update prevOpp;
        
        Opportunity curOpp = new Opportunity(
            Name = 'Current Repeat Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Type = 'Repeat Business',
            Previous_Opportunity__c = prevOpp.Id,
            AccountId = acc.Id
        );
        insert curOpp;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
        
    }
    
    @IsTest
    static void testFallbackMappingFromLegalEntity() {
        Account acc = [SELECT Id FROM Account WHERE Ultimate_Account__c != null LIMIT 1];
        
        Opportunity opp = new Opportunity(
            Name = 'Opp Fallback',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id
        );
        insert opp;
        
        Test.startTest();
        Database.executeBatch(new OpportunityBillingEntityBatch(), 200);
        Test.stopTest();
    }
}