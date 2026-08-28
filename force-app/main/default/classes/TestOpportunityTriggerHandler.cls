@isTest
public class TestOpportunityTriggerHandler {
    
    @testSetup
    static void setupData() {
                 
        // Create products (assumes your custom fields exist)
        Product2 prod1 = new Product2(
            Name = 'Test Product 1',
            Publication_Title__c = 'Lexology Panoramic: Foreign Investment Review',
            Financial_Year__c = '2024',
            Subscription_Model__c = 'Edition-Based',
            Division__c = 'Market Intelligence',
            Reporting_Stream__c = 'Expert Insight - Lexology Panoramic',
            ProductCode = '11118001010',
            IsActive = true
        );
        insert prod1;
        
        Product2 prod2 = new Product2(
            Name = 'Test Product 2',
            Publication_Title__c = 'Lexology Panoramic: Foreign Investment Review',
            Financial_Year__c = '2025',
            Subscription_Model__c = 'Edition-Based',
            Division__c = 'Market Intelligence',
            Reporting_Stream__c = 'Expert Insight - Lexology Panoramic',
            ProductCode = '11118001011',
            IsActive = true
        );
        insert prod2;
        
        // Create PricebookEntry records for each product in the standard price book
        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = '01s6g000009DokcAAC',
            Product2Id = prod1.Id,
            UnitPrice = 100,
            IsActive = true
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = '01s6g000009DokcAAC',
            Product2Id = prod2.Id,
            UnitPrice = 150,
            IsActive = true
        );
        insert new List<PricebookEntry>{pbe1, pbe2};
            
            // Create Opportunity and assign the pricebook
            Opportunity opp = new Opportunity(
                Name = 'Test Opportunity',
                CloseDate = Date.today().addDays(30),
                StageName = 'Identify',
                Pricebook2Id = '01s6g000009DokcAAC'
            );
        insert opp;
        
        // Create OpportunityLineItems linked to the opportunity and pricebook entries
        OpportunityLineItem oli1 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe1.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        OpportunityLineItem oli2 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe2.Id,
            Quantity = 2,
            UnitPrice = 150
        );
        insert new List<OpportunityLineItem>{oli1, oli2};
            }
    
    @isTest
    static void testDispatchRecalculatesDealYears() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        // Dispatches the Queueable; Test.stopTest() runs it synchronously
        ProcessLineItems.updateDealYears(new List<Id>{ opp.Id });
        System.assert(ProcessLineItems.processedOppIds.contains(opp.Id),
            'Dispatched opp id must be recorded in the per-transaction guard');

        // Second dispatch in the same transaction must be a no-op (no duplicate job)
        Integer jobsBefore = Limits.getQueueableJobs();
        ProcessLineItems.updateDealYears(new List<Id>{ opp.Id });
        System.assertEquals(jobsBefore, Limits.getQueueableJobs(),
            'Repeat dispatch for the same opp must not enqueue a second job');
        Test.stopTest();

        List<OpportunityLineItem> lineItems = [
            SELECT Deal_Start_Year__c, Deal_End_Year__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            ORDER BY Id
        ];

        for (OpportunityLineItem oli : lineItems) {
            // Adjust types and assertions based on your actual field type
            System.assertEquals(2024, Integer.valueOf(oli.Deal_Start_Year__c), 'Deal_Start_Year__c mismatch');
            System.assertEquals(2025, Integer.valueOf(oli.Deal_End_Year__c), 'Deal_End_Year__c mismatch');
        }
    }

    @isTest
    static void testNameOnlyUpdateDoesNotDispatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        opp.Name = 'Updated Opportunity';
        update opp; // no line-set change: gate must not dispatch the recalc
        System.assert(!ProcessLineItems.processedOppIds.contains(opp.Id),
            'A save with no line-item/Amount change must not dispatch the deal-years recalc');
        Test.stopTest();
    }

    @isTest
    static void testLineItemChangeDispatchesViaTrigger() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE UnitPrice = 100 LIMIT 1];

        Test.startTest();
        // Adding a line changes No_of_Line_Items__c / Amount, which system-fires the
        // Opportunity update trigger — the gate must dispatch the recalc.
        insert new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        Test.stopTest();

        System.assert(ProcessLineItems.processedOppIds.contains(opp.Id),
            'A line-item change must dispatch the deal-years recalc through the trigger');

        List<OpportunityLineItem> lineItems = [
            SELECT Deal_Start_Year__c, Deal_End_Year__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
        ];
        for (OpportunityLineItem oli : lineItems) {
            System.assertEquals(2024, Integer.valueOf(oli.Deal_Start_Year__c), 'Deal_Start_Year__c mismatch');
            System.assertEquals(2025, Integer.valueOf(oli.Deal_End_Year__c), 'Deal_End_Year__c mismatch');
        }
    }
}