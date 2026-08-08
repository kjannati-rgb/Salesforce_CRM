@isTest
public class TestALMSplitLineItemBatch {
    
    @testSetup
    static void setupData() {
        TestDataFactory.bypassAutomation();
        
        
        // Create products with relevant fields
        Product2 prod1 = new Product2(
            Name = 'Test Product 1',
            Publication_Title__c = 'Lexology Panoramic: Foreign Investment Review',
            Financial_Year__c = '2023',
            Subscription_Model__c = 'Edition-Based',
            Division__c = 'Market Intelligence',
            Reporting_Stream__c = 'Expert Insight - Lexology Panoramic',
            ProductCode = '11118001010',
            IsActive = true
        );
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
        insert new List<Product2>{prod1, prod2};
            
            // Create PricebookEntries
            PricebookEntry pbe1 = new PricebookEntry(
                Pricebook2Id = '01s6g000009DokcAAC',
                Product2Id = prod1.Id,
                UnitPrice = 200,
                IsActive = true
            );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = '01s6g000009DokcAAC',
            Product2Id = prod2.Id,
            UnitPrice = 300,
            IsActive = true
        );
        insert new List<PricebookEntry>{pbe1, pbe2};
            
            Account firm = new Account(Name = 'Test Account', BillingCountry = 'India',RecordTypeId='0126g000000OhUSAA0'); 	
        insert firm;
        Account office = new Account(Name = 'Test Account', BillingCountry = 'India',RecordTypeId = '0126g000000OhUTAA0',Ultimate_Account__c = firm.id); 
        insert office;
        
        // Create Opportunity with assigned pricebook
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            CloseDate = Date.today().addDays(30),
            StageName = 'Closed Won',
            Pricebook2Id = '01s6g000009DokcAAC',
            accountid = office.id
        );
        insert opp;
        
        // Create OpportunityLineItems for test products
        OpportunityLineItem oli1 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe1.Id,
            Quantity = 1,
            UnitPrice = 200,
            Year_2_Price__c = 210,
            Year_3_Price__c = 220,
            Start_Date__c = date.newInstance(2026, 03, 12),
            End_Date__c = date.newInstance(2029, 03, 11)
        );
        OpportunityLineItem oli2 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe2.Id,
            Quantity = 1,
            UnitPrice = 300,
            Year_2_Price__c = 310,
            Year_3_Price__c = 320,
            Start_Date__c = date.newInstance(2026, 03, 12),
            End_Date__c = date.newInstance(2029, 03, 11)
        );
        OpportunityLineItem oli3 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe2.Id,
            Quantity = 1,
            UnitPrice = 400,
            Year_2_Price__c = 410,
            Start_Date__c = date.newInstance(2026, 03, 12),
            End_Date__c = date.newInstance(2028, 03, 11)
        );
        insert new List<OpportunityLineItem>{oli1, oli2,oli3};
            }
    
    @isTest
    static void testBatchExecution() {
        // Run batch with small batch size to test execute method
        Test.startTest();
        ALMSplitLineItemBatch batch = new ALMSplitLineItemBatch();
        Database.executeBatch(batch, 5);
        Test.stopTest();
        
        // Verify that the line items are created correctly
        List<OpportunityLineItem> lineItems = [
            SELECT Id, OpportunityId,opportunity.owner.team__c, PricebookEntryId, Product2Id, ProductCode, Name, CurrencyIsoCode, Quantity, Discount, 
                   Subtotal, ListPrice, ServiceDate, HasRevenueSchedule, HasQuantitySchedule, Description, HasSchedule, CanUseQuantitySchedule, 
                   CanUseRevenueSchedule, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp, IsDeleted, LastViewedDate, LastReferencedDate, 
                   SBQQ__ParentID__c, SBQQ__QuoteLine__c, SBQQ__SubscriptionType__c, Financial_Year__c, Order_Year__c, Bio_Taker__c, Brand__c, Chapter_Region__c, Chapter_Type__c, 
                   Content_Channel__c, Books_Cards__c, Content_Type__c, Edition__c, Employee_Headcount__c, Free_Prose_Title__c, Free_Prose_Type__c, Number_of_Pages__c, 
                   Number_of_Regulators__c, Number_of_Vacancies__c, Number_of_Words__c, Pricing_Band__c, Product_Channel__c, Product_Text__c, Sun_Item_Code__c, Topic__c, 
                   Trainees__c, Content_Slot__c, Copies__c, Created_through__c, DATE_TEST__c, Distribution_Contact__c, Dynamics_Total_Amount__c, End_Date__c, Finance_Code__c, 
                   Schedule_Date__c, Start_Date__c, VAT__c, WWL_Product_Type__c, Workbooks_CRM_Historic_Pricing_Scheme__c, Workbooks_CRM_Legacy_ID__c, Additional_Description_1__c, 
                   Additional_Description_2__c, Chapter_Region_Code_for_SUN__c, Company2__c, Contract_Type_Code__c, Item_Code_Lookup__c, Order_Product__c, End_Date_SUN_Report__c, 
                   LBR_Legal_Entity_for_SUN__c, Original_End_Date__c, Original_Start_Date__c, QL_Net_Price__c, Start_Date_SUN_Report__c, Sum_of_Schedules__c, quantityRepeat__c, 
                   Submission_Deadline_Date__c, Delete_Product_Date__c, Delete_Today__c, Opportunity_Product_Number__c, Cancelled__c, Finance_Code_for_SUN__c, Re_sign_Revenue__c, 
                   New_Revenue__c, Fixed_Carried_Forward_Revenue__c, Subs_2021_Revenue__c, Start_Date_Month__c, Budget__c, Close_Date__c, Record_Type__c, Reporting_Stream_test__c, 
                   Financial_Year_Number__c, Reporting_Stream__c, Subs_2024_Revenue__c, Bypass_Validation_Triggered__c, Is_Automation_Bypassed__c, Renewed__c, Closed_Lost__c, 
                   Open__c, High_Risk__c, Low_Medium_Risk__c, Close_Stage_Amount__c, Evaluate_Stage_Amount__c, Closed_Won_Amount__c, Identify_Stage_Amount__c, Qualify_Stage_Amount__c, 
                   Open_Stage_Amount__c, Product_Brand__c, Company3__c, Product_Name__c, Closed_Lost_Amount__c, Product_Revenue_Date__c, Product_Revenue_Date_Month__c, 
                   Paid_Content_FY23_Revenue__c, UK_Revenue__c, HK_Revenue__c, Adobe_Sign_Content_Slot_Title__c, Sponsorship_Revenue__c, Delegate_Revenue__c, Chapter__c, 
                   Delegate_Revenue_HK__c, Sponsorship_Revenue_HK__c, Weighted_Product_WWL__c, Webinar_Date_Month__c, sbaa__ApprovalStatus__c, Webinar_Date_Quarter__c, 
                   Docket_Navigator_Licence_Bands__c, Webinar_Date__c, Forecast_Won_Amount__c, End_Date_SUN_Report_V2__c, Invoice_Date__c, Preferred_Invoice_Date__c, 
                   Start_Date_SUN_Report_V2__c, Old_Schedule_Date_Logic__c, Boardroom_Date__c, Actuals__c, OppOwnerID__c, OppRecordTypeName__c, Recalculation_Required__c, 
                   Target_Date__c, Subs_2024_Revenue_UK__c, Subs_2024_Revenue_HK__c, UK_Revenue_NB__c, UK_Revenue_RN__c, Number_of_Recruiters__c, Firm_Size__c, New_Business_Amount__c, 
                   Renewals_Amount__c, Weighted_Product__c, Subs_2023_Revenue__c, PrimaryContact__c, Effective_Subscription_Term__c, ROW_Revenue__c, Cvent_Event__c, Top_Level_Event__c,
                   Top_Level_Event_FY__c, Sponsorship_Delegate_Product__c, Subs_2023_Revenue_HK__c, Quote_Line_Effective_Quantity__c, Quote_Line_Quantity__c, Subs_2023_Revenue_UK__c,
                   Publication_Title_Edition__c, US_Revenue__c, Opportunity_Close_Date__c, Exchange_Rate__c, List_Price_GBP__c, Sales_Price_GBP__c, Total_Price_GBP__c, 
                   Product_Family__c, Mass_Update_Opportunity_Product__c, Deal_Type__c, Opportunity_Type_Name__c, Value_Changed__c, CPQ_Amendment_Invoice_Credit_Note__c, 
                   New_Business_Closed_won__c, Renewals_Closed_Won__c, Weighted_This_Month__c, Jurisdiction__c, Paid_Content_FY24_Revenue__c, X2023_Revenue__c, X2024_Revenue__c, 
                   Sponsorship_Revenue_UK__c, Sponsorship_Revenue_US__c, X2024_Renewal_Won__c, Lexology_Intelligence_Office_Tier__c, Previous_Product_Name__c, Scope__c, 
                   Reports_Covered__c, Segment_Index__c, Annual_Contract_Value__c, Active_Subscription__c, Deal_End_Year__c, Deal_Start_Year__c, Negotiate_Volume__c, 
                   ALM_ORD_Term_of_Order__c, ALM_Total_Contract_Value__c, Description__c, Discount_Amount__c, Dispatch_Method_Code__c, Expire_Date__c, Full_Contract_Value__c, 
                   ORD_Term_of_Order__c, PO__c, Prior_Order__c, Prior_Quantity__c, Promo_Code__c, Segment__c, Ship_To_Email__c, Ship_To_Phone__c, Ship_to_Address_2__c, 
                   Ship_to_Address__c, Ship_to_City__c, Ship_to_Company__c, Ship_to_Contact__c, Ship_to_Country__c, Ship_to_State__c, Ship_to_Subs__c, Ship_to_Zip_Code__c, 
                   Subs_Reference__c, Year_2_Price__c, Year_3_Price__c, Year_4_Price__c, Year_5_Price__c, of_Seats__c, AACV_Increase_Over_Prior_Year_Percentage__c, AACV__c, Multi__c, 
                   Number_of_Seats__c, metazoa_external_id__c, Change_in_Price__c, Segment_Information__c, Split_Year__c,unitprice
            FROM OpportunityLineItem WHERE Product2.Publication_Title__c = 'Lexology Panoramic: Foreign Investment Review'
            ORDER BY Product2.Financial_Year__c ASC
        ];
        system.debug('TestALMSplitLineItemBatch');
        system.debug(lineItems);
        // The start year should be the minimum financial year 2023 and end year the maximum 2025
        for (OpportunityLineItem oli : lineItems) 
        {
            system.debug('unit price and year check');
            if(oli.unitprice == 210)
            {
                System.assertEquals(210, oli.unitprice, 'Year 2 should be 210');
                System.assertEquals(2027, oli.Start_Date__c.year(), 'Year 2 should be 2027');
            }
            if(oli.unitprice == 220)
            {
                System.assertEquals(220, oli.unitprice, 'Year 2 should be 220');
                System.assertEquals(2028, oli.Start_Date__c.year(), 'Year 3 should be 2028');
                System.assertEquals(2029, oli.End_Date__c.year(), 'Year 3 end should be 2029');
            }
            if(oli.unitprice == 310)
            {
                System.assertEquals(310, oli.unitprice, 'Year 2 should be 310');
                System.assertEquals(2027, oli.Start_Date__c.year(), 'Year 2 should be 2027');
            }
            if(oli.unitprice == 320)
            {
                System.assertEquals(320, oli.unitprice, 'Year 3 should be 320');
                System.assertEquals(2028, oli.Start_Date__c.year(), 'Year 3 should be 2028');
                System.assertEquals(2029, oli.End_Date__c.year(), 'Year 3 end should be 2029');
            }
            
            if(oli.unitprice == 400)
            {
                System.assertEquals(400, oli.unitprice, 'Year 1 should be 400');
                System.assertEquals(2026, oli.Start_Date__c.year(), 'Year 1 should be 2026');
            }
            if(oli.unitprice == 410)
            {
                System.assertEquals(410, oli.unitprice, 'Year 2 should be 410');
                System.assertEquals(2027, oli.Start_Date__c.year(), 'Year 2 start should be 2027');
                System.assertEquals(2028, oli.End_Date__c.year(), 'Year 2 end should be 2028');
            }
            
            
        }
    }
}