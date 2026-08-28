@IsTest
private class OpportunityBillingEntityHandler_Test {

    @TestSetup
    static void bypassSetupAuto() {
        TestDataFactory.bypassAutomation();
    }

    @IsTest
    static void test_renewal_copies_previous() {
        Account a = new Account(Name = 'Test Account', BillingCountry = 'India'); insert a;

        Opportunity prev = new Opportunity(
            Name='Prev',
            StageName='Prospecting',
            CloseDate=Date.today(),
            Billing_Entity__c='GHK',
            AccountId=a.Id
        ); insert prev;

        // Previous_Opportunity__c lookup filter only accepts closed-won opportunities
        prev.StageName='Closed Won';
        update prev;

        Opportunity cur = new Opportunity(
            Name='Cur',
            StageName='Prospecting',
            CloseDate=Date.today(),
            Type='Renewal',
            Previous_Opportunity__c=prev.Id,
            AccountId=a.Id
        ); insert cur;

        // Second renewal referencing the same previous opp in the same transaction:
        // exercises the per-transaction previous-opportunity cache (no repeat query).
        Opportunity cur2 = new Opportunity(
            Name='Cur2',
            StageName='Prospecting',
            CloseDate=Date.today(),
            Type='Renewal',
            Previous_Opportunity__c=prev.Id,
            AccountId=a.Id
        ); insert cur2;
        System.assert(OpportunityBillingEntityHandler.prevOppCacheIds.contains(prev.Id),
            'Previous opportunity must be memoized for the transaction');
    }
    
    @IsTest
    static void test_renewal_copies_previous2() {
        Account a = new Account(Name = 'Test Account', BillingCountry = 'India'); insert a;
        
        Id newBusinessrecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('New_Business').getRecordTypeId();
        Opportunity prev = new Opportunity(
            RecordTypeID = newBusinessrecordTypeId,
            Name='Prev',
            StageName='Prospecting',
            CloseDate=Date.today(),
            Type='New Business',
            AccountId=a.Id
        ); insert prev;
        
        
        Product2 P =new Product2();
        P.name='TestJuneEdition3';
        P.Family='Events';
        P.ProductCode='11220033445Booksale';
        P.Subscription_Model__c ='Edition-Based';
        P.SBQQ__SubscriptionType__c ='One-time';
        P.SBQQ__PriceEditable__c=True;
        P.SBQQ__PricingMethodEditable__c=True;
        P.CanUseRevenueSchedule=True;
        P.Edition__c='Edition 2023';
        P.Financial_Year__c='2023';
        P.Revenue_Stream__c='Editorial';
        P.Division__c='Events';
        P.Reporting_Stream__c='Events - GBRR';
        P.Event_Location_Country__c='United States';
        insert P;
        
        Id StanPriceBookId=Test.getStandardPricebookId();
        
        PricebookEntry pbe = new PricebookEntry();
        pbe.Product2Id = P.id; // Replace with the actual Product2 Id
        pbe.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe.UnitPrice = 100.00; // Set the price for the PricebookEntry
        pbe.IsActive = true;
        insert pbe;
        
        SBQQ__quote__c prevQuote =new SBQQ__quote__c();
        prevQuote.SBQQ__Opportunity2__c=prev.Id;
        prevQuote.SBQQ__Primary__c=True;
        insert prevQuote;
        
        SBQQ__QuoteLine__c prevQuoteLines =new SBQQ__QuoteLine__c();
        prevQuoteLines.SBQQ__Product__c=P.id;
        //prevQuoteLines.SBQQ__ProductOption__c='';
        prevQuoteLines.SBQQ__CustomerPrice__c=pbe.UnitPrice;
        prevQuoteLines.SBQQ__Quantity__c=1;
        prevQuoteLines.SBQQ__NetPrice__c=pbe.UnitPrice;
        prevQuoteLines.SBQQ__ListPrice__c=pbe.UnitPrice;
        prevQuoteLines.SBQQ__Quote__c=prevQuote.id;
       
        Insert prevQuoteLines;
        OpportunityLineItem oli = new OpportunityLineItem();
        oli.Product2Id = P.id;
        oli.OpportunityId = prev.Id;
        oli.SBQQ__QuoteLine__c = prevQuoteLines.id;
        oli.PricebookEntryId = pbe.id;
        oli.Quantity = prevQuoteLines.SBQQ__Quantity__c;
        oli.UnitPrice = prevQuoteLines.SBQQ__NetPrice__c;
        insert oli;
       
    }
}