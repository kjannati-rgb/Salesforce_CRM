@isTest
public class OrderTriggerForRenewalOppTest {

    
    @isTest()
    Public Static void TestprocessOpportunities(){
        
        Id StanPriceBookId=Test.getStandardPricebookId();
        Account Ultimateacc =new Account();
        Ultimateacc.RecordTypeId='0126g000000OhUSAA0';
        Ultimateacc.Name='abc';
        //acc.Ultimate_Account__c=;
        Ultimateacc.BillingCity='Tirana';
        Ultimateacc.BillingCountry='Albania';
        insert Ultimateacc;
        Account acc =new Account();
        acc.Name='abc';
        acc.Ultimate_Account__c=Ultimateacc.Id;
        acc.BillingCity='Tirana';
        acc.BillingCountry='Albania';
        insert acc;
        
        
        Product2 P =new Product2();
        P.name='TestJune 2023';
        P.Family='Events';
        P.ProductCode='11220033445Booksale';
        P.Subscription_Model__c ='Edition-Based';
        P.SBQQ__SubscriptionType__c ='One-time';
        P.SBQQ__PriceEditable__c=True;
        P.SBQQ__PricingMethodEditable__c=True;
        P.CanUseRevenueSchedule=True;
        P.Edition__c='2023';
        P.Financial_Year__c='2023';
        P.Revenue_Stream__c='Editorial';
        P.Division__c='Events';
        P.Reporting_Stream__c='Events - GBRR';
        insert P;
        
        PricebookEntry pbe = new PricebookEntry();
        pbe.Product2Id = P.id; // Replace with the actual Product2 Id
        pbe.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe.UnitPrice = 100.00; // Set the price for the PricebookEntry
        pbe.CurrencyIsoCode='GBP';
        insert pbe;
        
        Product2 P1 =new Product2();
        P1.name='TestChildJune 2023';
        P1.Family='Events';
        P1.ProductCode='11220033445Booksale';
        P1.Subscription_Model__c ='Edition-Based';
        P1.SBQQ__SubscriptionType__c ='One-time';
        P1.SBQQ__PriceEditable__c=True;
        P1.SBQQ__PricingMethodEditable__c=True;
        P1.CanUseRevenueSchedule=True;
        P1.Edition__c='2023';
        P1.Financial_Year__c='2023';
        P1.Revenue_Stream__c='Editorial';
        P1.Division__c='Events';
        P1.Reporting_Stream__c='Events - GBRR';
        insert P1;
        
        PricebookEntry pbe1 = new PricebookEntry();
        pbe1.Product2Id = P1.id; // Replace with the actual Product2 Id
        pbe1.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe1.UnitPrice = 100.00; // Set the price for the PricebookEntry
        pbe1.CurrencyIsoCode='GBP';

        insert pbe1;
        
        
        Product2 P2 =new Product2();
        P2.name='TestJuly 2023';
        P2.Family='Events';
        P2.ProductCode='11220033445Booksale';
        P2.Subscription_Model__c ='Edition-Based';
        P2.SBQQ__SubscriptionType__c ='One-time';
        P2.SBQQ__PriceEditable__c=True;
        P2.SBQQ__PricingMethodEditable__c=True;
        P2.CanUseRevenueSchedule=True;
        P2.Edition__c='2023';
        P2.Financial_Year__c='2023';
        P2.Revenue_Stream__c='Editorial';
        P2.Division__c='Events';
        P2.Reporting_Stream__c='Events - GBRR';
        insert P2;
        
        PricebookEntry pbe2 = new PricebookEntry();
        pbe2.Product2Id = P2.id; // Replace with the actual Product2 Id
        pbe2.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe2.UnitPrice = 100.00; // Set the price for the PricebookEntry
        pbe2.CurrencyIsoCode='GBP';

        insert pbe2;
        
        
        Product2 P3 =new Product2();
        P3.name='TestChildJuly 2023';
        P3.Family='Events';
        P3.ProductCode='11220033445Booksale';
        P3.Subscription_Model__c ='Edition-Based';
        P3.SBQQ__SubscriptionType__c ='One-time';
        P3.SBQQ__PriceEditable__c=True;
        P3.SBQQ__PricingMethodEditable__c=True;
        P3.CanUseRevenueSchedule=True;
        P3.Edition__c='2023';
        P3.Financial_Year__c='2023';
        P3.Revenue_Stream__c='Editorial';
        P3.Division__c='Events';
        P3.Reporting_Stream__c='Events - GBRR';
        insert P3;
        
        PricebookEntry pbe3 = new PricebookEntry();
        pbe3.Product2Id = P3.id; // Replace with the actual Product2 Id
        pbe3.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe3.UnitPrice = 100.00; // Set the price for the PricebookEntry
        insert pbe3;
        
        SBQQ__ProductFeature__c testFeature1 = new SBQQ__ProductFeature__c(
            Name = 'Test Feature 1',
            SBQQ__ConfiguredSKU__c = P.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            
            SBQQ__Number__c = 123
        );
        insert testFeature1;
        
        SBQQ__ProductOption__c testOption1 = new SBQQ__ProductOption__c( SBQQ__Number__c=10,
        SBQQ__ConfiguredSKU__c=P.Id,
        SBQQ__OptionalSKU__c=P1.Id,
        SBQQ__Quantity__c=10,
        SBQQ__Feature__c=testFeature1.id);
        insert testOption1 ;
        
        SBQQ__ProductFeature__c testFeature2 = new SBQQ__ProductFeature__c(
            Name = 'Test Feature 2',
            SBQQ__ConfiguredSKU__c = P.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            
            SBQQ__Number__c = 123
        );
        insert testFeature2;
        
        SBQQ__ProductOption__c testOption2 = new SBQQ__ProductOption__c( SBQQ__Number__c=10,
        SBQQ__ConfiguredSKU__c=P.Id,
        SBQQ__OptionalSKU__c=P2.Id,
        SBQQ__Quantity__c=10,
        SBQQ__Feature__c=testFeature1.id);
        insert testOption2 ;
        
        SBQQ__ProductRule__c pr1=new SBQQ__ProductRule__c(Name='Rule1',
                                                          SBQQ__ErrorMessage__c='Test',
                                                          SBQQ__Type__c='Alert',
                                                          SBQQ__Scope__c='Product',
                                                          SBQQ__ConditionsMet__c='All',
                                                          SBQQ__EvaluationEvent__c='Save');
        insert pr1;
        
        
        SBQQ__ConfigurationRule__c testRule1 = new SBQQ__ConfigurationRule__c(
                SBQQ__Active__c = true,
                SBQQ__ProductRule__c =pr1.id,
                SBQQ__Product__c = P.Id,
                SBQQ__ProductFeature__c = testFeature1.Id
            );
        insert testRule1;
        
        SBQQ__OptionConstraint__c testConstraint1 = new SBQQ__OptionConstraint__c(
            SBQQ__Active__c = true,
            SBQQ__ConstrainingOption__c = testOption1.Id,
            SBQQ__ConstrainedOption__c = testOption2.Id,
            
            SBQQ__ConfiguredSKU__c = P.Id

        );
        insert testConstraint1;
        
        
        Content_Slots__c Cs1 =new Content_Slots__c();
        Cs1.Publication__c=P.id;
        Cs1.Jurisdiction__c='Abu Dhabi';
        Cs1.Name='Abu Dhabi';
        insert Cs1;

        
        
        Opportunity PrevOpp=new Opportunity();
        PrevOpp.name='opp Test 2023';
        PrevOpp.CloseDate=System.today();
        PrevOpp.LeadSource='Renewal';
        PrevOpp.AccountId=acc.id;
        PrevOpp.Pricebook2Id=StanPriceBookId;
        PrevOpp.CurrencyIsoCode='GBP';
        PrevOpp.StageName='Closed Won';
        PrevOpp.Type='New Business';
        PrevOpp.Deal_Length__c=12;
        PrevOpp.SBQQ__Ordered__c=true;
        insert PrevOpp;
        
        SBQQ__quote__c prevQuote =new SBQQ__quote__c();
        prevQuote.SBQQ__Opportunity2__c=PrevOpp.Id;
        prevQuote.SBQQ__Primary__c=True;
        prevQuote.CurrencyIsoCode='GBP';
        insert prevQuote;
        list<SBQQ__QuoteLine__c>quotelinesList=new list<SBQQ__QuoteLine__c>();
        SBQQ__QuoteLine__c prevQuoteLines =new SBQQ__QuoteLine__c();
        prevQuoteLines.SBQQ__Product__c=P.id;
        //prevQuoteLines.SBQQ__ProductOption__c='';
        prevQuoteLines.SBQQ__CustomerPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__Quantity__c=1;
        prevQuoteLines.SBQQ__NetPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__ListPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__Quote__c=prevQuote.id;
        
        quotelinesList.add(prevQuoteLines);
       
        //Insert prevQuoteLines;
        
       /* SBQQ__QuoteLine__c prevQuoteLines1 =new SBQQ__QuoteLine__c();
        prevQuoteLines1.SBQQ__Product__c=P1.id;
        prevQuoteLines1.SBQQ__ProductOption__c=testOption1.id;
        prevQuoteLines1.SBQQ__CustomerPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__Quantity__c=1;
        prevQuoteLines1.SBQQ__NetPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__ListPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__Quote__c=prevQuote.id;
        
        quotelinesList.add(prevQuoteLines1);  */      
       
        //Insert prevQuoteLines1;
        INSERT quotelinesList;
         Application_Settings__c appSetting= new Application_Settings__c();
        appSetting.Disable_Triggers__c=false;
        
        Trigger_Settings__c triggersetting = new Trigger_Settings__c();
        triggersetting.Trigger_Name__c = 'OrderTriggerForRenewalOpp';
        triggersetting.Is_Active__c = true;
        insert triggersetting;
        
        
        map<Id,Order>OldTriggerMap=new Map<Id,Order>();
        list<order>newOrders=new list<Order>();
        User u =new User();
        u = [Select Id,name from User where id=: userinfo.getUserId()];
        Order o=new Order();
        o.AccountId=acc.id;
        //o.Contact__c=;
        o.Status='Draft';
        o.Type='New';
        o.LastModifiedById=u.id;
        o.IsReductionOrder=false;
        o.EffectiveDate=system.today();
        o.OpportunityId=PrevOpp.id;
        o.CurrencyIsoCode='GBP';
        o.Pricebook2Id=StanPriceBookId;
        insert o;
        
        
        OrderItem oi=new OrderItem();
        oi.Product2Id=P.Id;
        oi.Quantity=1;
        oi.OrderId=o.Id;
        oi.PricebookEntryId=pbe.Id;
        oi.UnitPrice=100;
        insert oi;
        /*OrderItem oi1=new OrderItem();
        oi1.Product2Id=P1.Id;
        oi1.Quantity=1;
        oi1.OrderId=o.Id;
        oi1.PricebookEntryId=pbe1.Id;
        oi1.UnitPrice=100;
        insert oi1;
        */
        
        
        Test.startTest();
        order or1 = [select id ,status from order where id =:o.id];
        or1.StatusCode = 'Activated';
        or1.Status='Activated';
        Database.update(or1,true);
        
         
        Test.StopTest();
        system.debug('or1'+or1);
        //o.activateOrder();

       
        /*Order o2=new order();
        o2.id=o.id;
        o2.status='Activated';
        Update o2;*/
        //Test.startTest();
        //order or1 = [select id ,status from order where id =:o.id];
        //or1.Status='Activated';
        //oi.SBQQ__Status__c='Activated';
        //Database.update(or1,true);
        
         
        //Test.StopTest();
        //system.debug('o2'+o);
        //system.debug('or4'+or4);
        //OldTriggerMap.put(o.id,o);
        //o.Status='Activated';
        
        //update o;
        //newOrders.add(o);
       
      
      
        Set<Id> oppIds = new Set<Id>();
        oppIds.add(o.OpportunityId);
        
        Map<Id,Id>OwnerIdBYoppoId=new Map<Id,Id>();
        OwnerIdBYoppoId.put(o.OpportunityId, o.Id);
        Map<Id,Id>OrderIdBYoppoId=new Map<Id,Id>();
        OrderIdBYoppoId.put(o.OpportunityId,o.id);
        Map<Id, Id> reducedOrderIdBYoppoId=new Map<Id, Id>();
        reducedOrderIdBYoppoId.put(o.OriginalOrderId,o.id);
        RenewalOpportunityHandler2.processOpportunities(OwnerIdBYoppoId,OrderIdBYoppoId);

    }
    
    
    
    @isTest()
    Public Static void TestprocessOpportunitiesElse(){
        
        Id StanPriceBookId=Test.getStandardPricebookId();
        Account Ultimateacc =new Account();
        Ultimateacc.RecordTypeId='0126g000000OhUSAA0';
        Ultimateacc.Name='abc';
        //acc.Ultimate_Account__c=;
        Ultimateacc.BillingCity='Tirana';
        Ultimateacc.BillingCountry='Albania';
        insert Ultimateacc;
        Account acc =new Account();
        acc.Name='abc';
        acc.Ultimate_Account__c=Ultimateacc.Id;
        acc.BillingCity='Tirana';
        acc.BillingCountry='Albania';
        insert acc;
        
        
        Product2 P =new Product2();
        P.name='TestJune Edition 3';
        P.Family='Events';
        P.ProductCode='11220033445Booksale';
        P.Subscription_Model__c ='Edition-Based';
        P.SBQQ__SubscriptionType__c ='One-time';
        P.SBQQ__PriceEditable__c=True;
        P.SBQQ__PricingMethodEditable__c=True;
        P.CanUseRevenueSchedule=True;
        P.Edition__c='3';
        P.Financial_Year__c='2023';
        P.Revenue_Stream__c='Editorial';
        P.Division__c='Events';
        P.Reporting_Stream__c='Events - GBRR';
        insert P;
        
        PricebookEntry pbe = new PricebookEntry();
        pbe.Product2Id = P.id; // Replace with the actual Product2 Id
        pbe.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe.UnitPrice = 100.00; // Set the price for the PricebookEntry
        pbe.CurrencyIsoCode='GBP';
        insert pbe;
        
        Product2 P1 =new Product2();
        P1.name='TestChildJune Edition 3';
        P1.Family='Events';
        P1.ProductCode='11220033445Booksale';
        P1.Subscription_Model__c ='Edition-Based';
        P1.SBQQ__SubscriptionType__c ='One-time';
        P1.SBQQ__PriceEditable__c=True;
        P1.SBQQ__PricingMethodEditable__c=True;
        P1.CanUseRevenueSchedule=True;
        P1.Edition__c='3';
        P1.Financial_Year__c='2023';
        P1.Revenue_Stream__c='Editorial';
        P1.Division__c='Events';
        P1.Reporting_Stream__c='Events - GBRR';
        insert P1;
        
        PricebookEntry pbe1 = new PricebookEntry();
        pbe1.Product2Id = P1.id; // Replace with the actual Product2 Id
        pbe1.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe1.UnitPrice = 100.00; // Set the price for the PricebookEntry
        insert pbe1;
        
        
        Product2 P2 =new Product2();
        P2.name='TestJuly Edition 3';
        P2.Family='Events';
        P2.ProductCode='11220033445Booksale';
        P2.Subscription_Model__c ='Edition-Based';
        P2.SBQQ__SubscriptionType__c ='One-time';
        P2.SBQQ__PriceEditable__c=True;
        P2.SBQQ__PricingMethodEditable__c=True;
        P2.CanUseRevenueSchedule=True;
        P2.Edition__c='3';
        P2.Financial_Year__c='2023';
        P2.Revenue_Stream__c='Editorial';
        P2.Division__c='Events';
        P2.Reporting_Stream__c='Events - GBRR';
        insert P2;
        
        PricebookEntry pbe2 = new PricebookEntry();
        pbe2.Product2Id = P2.id; // Replace with the actual Product2 Id
        pbe2.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe2.UnitPrice = 100.00; // Set the price for the PricebookEntry
        insert pbe2;
        
        
        Product2 P3 =new Product2();
        P3.name='TestChildJuly Edition 3';
        P3.Family='Events';
        P3.ProductCode='11220033445Booksale';
        P3.Subscription_Model__c ='Edition-Based';
        P3.SBQQ__SubscriptionType__c ='One-time';
        P3.SBQQ__PriceEditable__c=True;
        P3.SBQQ__PricingMethodEditable__c=True;
        P3.CanUseRevenueSchedule=True;
        P3.Edition__c='3';
        P3.Financial_Year__c='2023';
        P3.Revenue_Stream__c='Editorial';
        P3.Division__c='Events';
        P3.Reporting_Stream__c='Events - GBRR';
        insert P3;
        
        PricebookEntry pbe3 = new PricebookEntry();
        pbe3.Product2Id = P3.id; // Replace with the actual Product2 Id
        pbe3.Pricebook2Id = StanPriceBookId; // Replace with the actual Pricebook2 Id
        pbe3.UnitPrice = 100.00; // Set the price for the PricebookEntry
        insert pbe3;
        
        SBQQ__ProductFeature__c testFeature1 = new SBQQ__ProductFeature__c(
            Name = 'Test Feature 1',
            SBQQ__ConfiguredSKU__c = P.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            
            SBQQ__Number__c = 123
        );
        insert testFeature1;
        
        SBQQ__ProductOption__c testOption1 = new SBQQ__ProductOption__c( SBQQ__Number__c=10,
        SBQQ__ConfiguredSKU__c=P.Id,
        SBQQ__OptionalSKU__c=P1.Id,
        SBQQ__Quantity__c=10,
        SBQQ__Feature__c=testFeature1.id);
        insert testOption1 ;
        
        SBQQ__ProductFeature__c testFeature2 = new SBQQ__ProductFeature__c(
            Name = 'Test Feature 2',
            SBQQ__ConfiguredSKU__c = P.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            
            SBQQ__Number__c = 123
        );
        insert testFeature2;
        
        SBQQ__ProductOption__c testOption2 = new SBQQ__ProductOption__c( SBQQ__Number__c=10,
        SBQQ__ConfiguredSKU__c=P.Id,
        SBQQ__OptionalSKU__c=P2.Id,
        SBQQ__Quantity__c=10,
        SBQQ__Feature__c=testFeature1.id);
        insert testOption2 ;
        
        SBQQ__ProductRule__c pr1=new SBQQ__ProductRule__c(Name='Rule1',
                                                          SBQQ__ErrorMessage__c='Test',
                                                          SBQQ__Type__c='Alert',
                                                          SBQQ__Scope__c='Product',
                                                          SBQQ__ConditionsMet__c='All',
                                                          SBQQ__EvaluationEvent__c='Save');
        insert pr1;
        
        
        SBQQ__ConfigurationRule__c testRule1 = new SBQQ__ConfigurationRule__c(
                SBQQ__Active__c = true,
                SBQQ__ProductRule__c =pr1.id,
                SBQQ__Product__c = P.Id,
                SBQQ__ProductFeature__c = testFeature1.Id
            );
        insert testRule1;
        
        SBQQ__OptionConstraint__c testConstraint1 = new SBQQ__OptionConstraint__c(
            SBQQ__Active__c = true,
            SBQQ__ConstrainingOption__c = testOption1.Id,
            SBQQ__ConstrainedOption__c = testOption2.Id,
            
            SBQQ__ConfiguredSKU__c = P.Id

        );
        insert testConstraint1;
        
        
        Content_Slots__c Cs1 =new Content_Slots__c();
        Cs1.Publication__c=P.id;
        Cs1.Jurisdiction__c='Abu Dhabi';
        Cs1.Name='Abu Dhabi';
        insert Cs1;

        
        
        Opportunity PrevOpp=new Opportunity();
        PrevOpp.name='opp Test 2023';
        PrevOpp.CloseDate=System.today();
        PrevOpp.LeadSource='Renewal';
        PrevOpp.AccountId=acc.id;
        PrevOpp.Pricebook2Id=StanPriceBookId;
        PrevOpp.CurrencyIsoCode='GBP';
        PrevOpp.StageName='Closed Won';
        PrevOpp.Type='New Business';
        PrevOpp.Deal_Length__c=12;
        PrevOpp.SBQQ__Ordered__c=true;
        insert PrevOpp;
        
        SBQQ__quote__c prevQuote =new SBQQ__quote__c();
        prevQuote.SBQQ__Opportunity2__c=PrevOpp.Id;
        prevQuote.SBQQ__Primary__c=True;
        prevQuote.CurrencyIsoCode='GBP';
        insert prevQuote;
        
      /*  SBQQ__QuoteLine__c prevQuoteLines =new SBQQ__QuoteLine__c();
        prevQuoteLines.SBQQ__Product__c=P.id;
        //prevQuoteLines.SBQQ__ProductOption__c='';
        prevQuoteLines.SBQQ__CustomerPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__Quantity__c=1;
        prevQuoteLines.SBQQ__NetPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__ListPrice__c=pbe2.UnitPrice;
        prevQuoteLines.SBQQ__Quote__c=prevQuote.id;
        
        
       
        Insert prevQuoteLines;*/
        
        SBQQ__QuoteLine__c prevQuoteLines1 =new SBQQ__QuoteLine__c();
        prevQuoteLines1.SBQQ__Product__c=P1.id;
        prevQuoteLines1.SBQQ__ProductOption__c=testOption1.id;
        prevQuoteLines1.SBQQ__CustomerPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__Quantity__c=1;
        prevQuoteLines1.SBQQ__NetPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__ListPrice__c=pbe1.UnitPrice;
        prevQuoteLines1.SBQQ__Quote__c=prevQuote.id;
        
        
       
        Insert prevQuoteLines1;
        
         Application_Settings__c appSetting= new Application_Settings__c();
        appSetting.Disable_Triggers__c=false;
        
        Trigger_Settings__c triggersetting = new Trigger_Settings__c();
        triggersetting.Trigger_Name__c = 'OrderTriggerForRenewalOpp';
        triggersetting.Is_Active__c = true;
        insert triggersetting;
        
        
        map<Id,Order>OldTriggerMap=new Map<Id,Order>();
        list<order>newOrders=new list<Order>();
        User u =new User();
        u = [Select Id,name from User where id=: userinfo.getUserId()];
        Order o=new Order();
        o.AccountId=acc.id;
        //o.Contact__c=;
        o.Status='Draft';
        o.Type='New';
        o.LastModifiedById=u.id;
        o.IsReductionOrder=false;
        o.EffectiveDate=system.today();
        o.OpportunityId=PrevOpp.id;
        o.CurrencyIsoCode='GBP';
        o.Pricebook2Id=StanPriceBookId;
        insert o;
        
        
        OrderItem oi=new OrderItem();
        oi.Product2Id=P.Id;
        oi.Quantity=1;
        oi.OrderId=o.Id;
        oi.PricebookEntryId=pbe.Id;
        oi.UnitPrice=100;
        insert oi;
        
        
        
        Test.startTest();
        order or1 = [select id ,status from order where id =:o.id];
        or1.StatusCode = 'Activated';
        or1.Status='Activated';
        Database.update(or1,true);
        
         
        Test.StopTest();
        system.debug('or1'+or1);
        //o.activateOrder();

       
        /*Order o2=new order();
        o2.id=o.id;
        o2.status='Activated';
        Update o2;*/
        //Test.startTest();
        //order or1 = [select id ,status from order where id =:o.id];
        //or1.Status='Activated';
        //oi.SBQQ__Status__c='Activated';
        //Database.update(or1,true);
        
         
        //Test.StopTest();
        //system.debug('o2'+o);
        //system.debug('or4'+or4);
        //OldTriggerMap.put(o.id,o);
        //o.Status='Activated';
        
        //update o;
        //newOrders.add(o);
       
      
      
        Set<Id> oppIds = new Set<Id>();
        oppIds.add(o.OpportunityId);
        
        Map<Id,Id>OwnerIdBYoppoId=new Map<Id,Id>();
        OwnerIdBYoppoId.put(o.OpportunityId, o.Id);
        Map<Id,Id>OrderIdBYoppoId=new Map<Id,Id>();
        OrderIdBYoppoId.put(o.OpportunityId,o.id);
        Map<Id, Id> reducedOrderIdBYoppoId=new Map<Id, Id>();
        reducedOrderIdBYoppoId.put(o.OriginalOrderId,o.id);
        RenewalOpportunityHandler2.processOpportunities(OwnerIdBYoppoId,OrderIdBYoppoId);

    }
    
    
    
}