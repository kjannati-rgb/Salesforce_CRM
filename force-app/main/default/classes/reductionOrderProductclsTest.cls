@isTest
public class reductionOrderProductclsTest {

    @TestSetup
    static void bypassSetupAuto() {
        TestDataFactory.bypassAutomation();
    }

    public static testMethod void testreductionOrderProduct(){
        
        // Insert Account
        
        Account a = new Account();
        a.Name = 'Test Account';
        a.Alternative_Name__c = 'Test Account';
        a.Industry = 'Aerospace & Defence';
        a.Organisation_Type__c = 'Company';
        a.BillingCountry = 'Aruba';
        insert a;
        
        // Insert Opportunity 
        Opportunity opp = new Opportunity();
        opp.StageName = 'Sourcing Demand';
        opp.CloseDate = system.today() + 4;
        opp.AccountId = a.Id;
        opp.Type = 'Auto-Renewal';
        opp.ForecastCategoryName = 'Omitted';
        opp.Name = 'Test Opportunity Triggers';
        
        insert opp;
        
        
        // Insert Product
        Product2 p = new Product2();
        p.Name = ' Test Product';
        p.Division__c = 'Benchmarking';
        p.Description='Test Product Entry 1';
        p.productCode = 'ABC';
        p.Reporting_Stream__c = 'Benchmarking - WWL';
        p.isActive = true;
        insert p;
        
        Id pricebookId = Test.getStandardPricebookId();
        
        // Insert PricebookEntry
        
        PricebookEntry standardPrice = new PricebookEntry();
        standardPrice.Pricebook2Id = pricebookId;
        standardPrice.Product2Id = p.Id;
        standardPrice.UnitPrice = 1;
        standardPrice.IsActive = true;
        standardPrice.UseStandardPrice = false;
        insert standardPrice ;
        
        // Insert Order
        
        Order o1 = new Order();
        o1.Name = 'Test Order ';
        o1.OpportunityId = opp.Id;
        o1.Status = 'Draft';
        o1.Type = 'New';
        o1.EffectiveDate = system.today();
        o1.EndDate = system.today() + 4;
        o1.AccountId = a.id;     
        o1.Pricebook2Id =  pricebookId ;
        system.debug(o1);
        insert o1;
        // Insert Order Item
        
        OrderItem i = new OrderItem();
        i.OrderId = o1.id;
        i.PricebookEntryId = standardPrice.Id;
        i.Quantity = 24;
        i.UnitPrice = 240;
        insert i;
        
        
        o1.Status = 'Activated';
        update o1;
        
        
        
        // Insert Order
        
        Order o = new Order();
        o.Name = 'Test Order ';
        o.OpportunityId = opp.Id;
        o.OriginalOrderId = o1.Id;
        o.IsReductionOrder = true;
        o.Status = 'Draft';
        o.EffectiveDate = system.today();
        o.EndDate = system.today() + 4;
        o.AccountId = a.id;        
        insert o;
        list<orderProductListWrapper> productListwrapper = new list<orderProductListWrapper>();
        orderProductListWrapper productlst = new orderProductListWrapper();
            productlst.product = i;
            productlst.QuantitytoReduce = 1;
        productListwrapper.add(productlst);
        String str = JSON.serialize(productListwrapper);
        system.debug(str);
        Test.startTest();
        reductionOrderProductcls reduction = new reductionOrderProductcls();
        reductionOrderProductcls.OrderitemListWrapper(o.Id);
		reductionOrderProductcls.OrderitemList(o.Id);
        reductionOrderProductcls.OrderValue(o.Id);
        reductionOrderProductcls.insertprodduct(str,o.Id);
        Test.stopTest();
    }
    
     public class orderProductListWrapper{
        @AuraEnabled
        public OrderItem product{get;set;}
        @AuraEnabled
        public Decimal QuantitytoReduce{get;set;}
    }
    
}