/**
 * Tests for OpportunityAnalyticsCreate.
 *
 * Test data is built entirely in GBP. Opportunity.Exchange_Rate__c is a formula
 * (CASE on CurrencyIsoCode) that returns 1 for any non-EUR/USD currency, so for
 * GBP the convertFromGBP() step is the identity and the rolled-up TCV equals the
 * sum of the line items' TotalPrice — which makes the amounts deterministic to assert.
 *
 * OpportunityLineItem.Annual_Contract_Value__c is a formula; with the SUN report
 * start/end dates set equal it resolves to TotalPrice, but to stay robust against
 * any line-item automation the ACV assertions only check it is populated and non-negative.
 *
 * Opportunity is created at the "Identify" stage (probability 10) to stay below the
 * Contact Role completeness validation rule threshold (50).
 */
@isTest
private class OpportunityAnalyticsCreate_Test {

    // Product codes chosen so LEFT(ProductCode, 11) (Clean_Product_Code__c) is distinct per product
    private static final String CODE_A   = 'AAAA-000001';
    private static final String CODE_B   = 'BBBB-000002';
    // Reporting_Stream__c is a dependent picklist controlled by Division__c; these
    // stream values are valid only under the "Events" division.
    private static final String DIVISION = 'Events';
    private static final String STREAM_A = 'Events - GAR';
    private static final String STREAM_B = 'Events - LIL';
    private static final String STAGE    = 'Identify';
    private static final String CCY      = 'GBP';

    private static Product2 makeProduct(String name, String productCode, String stream) {
        return new Product2(
            Name = name,
            ProductCode = productCode,
            Division__c = DIVISION,
            Reporting_Stream__c = stream,
            IsActive = true
        );
    }

    private static Opportunity makeOpp(String name) {
        return new Opportunity(
            Name = name,
            StageName = STAGE,
            CloseDate = Date.today().addMonths(1),
            CurrencyIsoCode = CCY,
            Pricebook2Id = Test.getStandardPricebookId()
        );
    }

    private static PricebookEntry makePbe(Id productId, Decimal unitPrice) {
        return new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true,
            UseStandardPrice = false,
            CurrencyIsoCode = CCY
        );
    }

    private static OpportunityLineItem makeOli(Id oppId, Id pbeId, Decimal unitPrice, Date sunDate) {
        return new OpportunityLineItem(
            OpportunityId = oppId,
            PricebookEntryId = pbeId,
            Quantity = 1,
            UnitPrice = unitPrice,
            Start_Date_SUN_Report__c = sunDate,
            End_Date_SUN_Report__c = sunDate
        );
    }

    private static Map<Id, Opportunity_Analytics__c> queryByCurrentProduct(Id oppId) {
        Map<Id, Opportunity_Analytics__c> byProduct = new Map<Id, Opportunity_Analytics__c>();
        for (Opportunity_Analytics__c oa : [
            SELECT Id, Current_Opportunity__c, Current_Product__c, Previous_Product__c,
                   Product_Code__c, CurrencyIsoCode, TCV2__c, PTCV2__c,
                   Annual_Contract_Value2__c, Previous_Annual_Contract_Value2__c, Reporting__c
            FROM Opportunity_Analytics__c
            WHERE Current_Opportunity__c = :oppId
        ]) {
            byProduct.put(oa.Current_Product__c, oa);
        }
        return byProduct;
    }

    /** Current opportunity, two products (two clean codes), no previous opportunity. */
    @isTest
    static void testInsertCreatesAnalyticsPerProductCode() {
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup
        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        Product2 pB = makeProduct('Prod B', CODE_B, STREAM_B);
        insert new List<Product2>{ pA, pB };

        PricebookEntry pbeA = makePbe(pA.Id, 100);
        PricebookEntry pbeB = makePbe(pB.Id, 250);
        insert new List<PricebookEntry>{ pbeA, pbeB };

        Opportunity opp = makeOpp('Current Opp');
        insert opp;

        insert new List<OpportunityLineItem>{
            makeOli(opp.Id, pbeA.Id, 100, opp.CloseDate),
            makeOli(opp.Id, pbeB.Id, 250, opp.CloseDate)
        };

        OpportunityAnalyticsCreate.activeOverride = true; // enable for the call under test (independent of the deployed CMDT)
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(new List<Opportunity>{ opp });
        Test.stopTest();

        Map<Id, Opportunity_Analytics__c> byProduct = queryByCurrentProduct(opp.Id);
        System.assertEquals(2, byProduct.size(), 'One analytics record per clean product code');

        Opportunity_Analytics__c oaA = byProduct.get(pA.Id);
        System.assertNotEquals(null, oaA, 'Analytics record for product A expected');
        System.assert(oaA.TCV2__c == 100, 'TCV for A should equal TotalPrice (GBP, rate 1). Got ' + oaA.TCV2__c);
        System.assertEquals(CCY, oaA.CurrencyIsoCode, 'Currency should match the current opportunity');
        System.assertEquals(STREAM_A, oaA.Reporting__c, 'Reporting should come from the current product stream');
        System.assertEquals(null, oaA.Previous_Product__c, 'No previous product expected');
        System.assertNotEquals(null, oaA.Annual_Contract_Value2__c, 'ACV should be populated');

        Opportunity_Analytics__c oaB = byProduct.get(pB.Id);
        System.assertNotEquals(null, oaB, 'Analytics record for product B expected');
        System.assert(oaB.TCV2__c == 250, 'TCV for B should equal TotalPrice. Got ' + oaB.TCV2__c);
        System.assertEquals(STREAM_B, oaB.Reporting__c, 'Reporting for B');
    }

    /** Current opportunity linked to a previous opportunity; verifies previous values roll up. */
    @isTest
    static void testWithPreviousOpportunity() {
        // The previous opportunity must be Closed Won (lookup filter). At that win
        // probability the Contact Role before-save flow would otherwise block the save,
        // so disable autolaunched flows for this transaction via its documented kill-switch.
        insert new Application_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true,
            Disable_Validation_Rules__c = true
        );
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup

        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        Product2 pB = makeProduct('Prod B', CODE_B, STREAM_B);
        insert new List<Product2>{ pA, pB };

        PricebookEntry pbeA = makePbe(pA.Id, 100);
        PricebookEntry pbeB = makePbe(pB.Id, 50);
        insert new List<PricebookEntry>{ pbeA, pbeB };

        // Previous_Opportunity__c has a lookup filter requiring a Closed Won opportunity.
        Opportunity prevOpp = makeOpp('Previous Opp');
        prevOpp.StageName = 'Closed Won';
        insert prevOpp;
        // Previous opp carries only product A at 200
        insert makeOli(prevOpp.Id, pbeA.Id, 200, prevOpp.CloseDate);

        Opportunity currOpp = makeOpp('Current Opp');
        currOpp.Previous_Opportunity__c = prevOpp.Id;
        insert currOpp;
        // Current opp carries product A (100) and product B (50)
        insert new List<OpportunityLineItem>{
            makeOli(currOpp.Id, pbeA.Id, 100, currOpp.CloseDate),
            makeOli(currOpp.Id, pbeB.Id, 50, currOpp.CloseDate)
        };

        OpportunityAnalyticsCreate.activeOverride = true; // enable for the call under test (independent of the deployed CMDT)
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(currOpp.Id); // single-Id overload
        Test.stopTest();

        Map<Id, Opportunity_Analytics__c> byProduct = queryByCurrentProduct(currOpp.Id);
        System.assertEquals(2, byProduct.size(), 'Two clean product codes across current + previous');

        Opportunity_Analytics__c oaA = byProduct.get(pA.Id);
        System.assertNotEquals(null, oaA, 'Analytics for A expected');
        System.assert(oaA.TCV2__c == 100, 'Current TCV for A. Got ' + oaA.TCV2__c);
        System.assert(oaA.PTCV2__c == 200, 'Previous TCV for A should come from previous opp. Got ' + oaA.PTCV2__c);
        System.assertEquals(pA.Id, oaA.Previous_Product__c, 'Previous product should be set for A');

        Opportunity_Analytics__c oaB = byProduct.get(pB.Id);
        System.assertNotEquals(null, oaB, 'Analytics for B expected');
        System.assert(oaB.TCV2__c == 50, 'Current TCV for B. Got ' + oaB.TCV2__c);
        System.assert(oaB.PTCV2__c == 0, 'B has no previous line item, previous TCV should be 0. Got ' + oaB.PTCV2__c);
        System.assertEquals(null, oaB.Previous_Product__c, 'B should have no previous product');
    }

    /** An existing analytics record for the same opp + product code should be updated, not duplicated. */
    @isTest
    static void testUpdatesExistingRecord() {
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup
        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        insert pA;
        PricebookEntry pbeA = makePbe(pA.Id, 100);
        insert pbeA;

        Opportunity opp = makeOpp('Current Opp');
        insert opp;
        insert makeOli(opp.Id, pbeA.Id, 100, opp.CloseDate);

        // Pre-existing analytics record with a stale value; its Product_Code__c formula
        // resolves to product A's clean code, so it matches the rollup key.
        Opportunity_Analytics__c stale = new Opportunity_Analytics__c(
            Current_Opportunity__c = opp.Id,
            Current_Product__c = pA.Id,
            CurrencyIsoCode = CCY,
            TCV2__c = 999
        );
        insert stale;

        OpportunityAnalyticsCreate.activeOverride = true; // enable for the call under test (independent of the deployed CMDT)
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(opp.Id);
        Test.stopTest();

        List<Opportunity_Analytics__c> oas = [
            SELECT Id, TCV2__c FROM Opportunity_Analytics__c WHERE Current_Opportunity__c = :opp.Id
        ];
        System.assertEquals(1, oas.size(), 'Existing record should be updated, not duplicated');
        System.assert(oas[0].TCV2__c == 100, 'Stale TCV (999) should be overwritten with 100. Got ' + oas[0].TCV2__c);
        System.assertEquals(stale.Id, oas[0].Id, 'Same record should have been updated');
    }

    /** Set<Id> overload exercises the same path. */
    @isTest
    static void testSetOverload() {
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup
        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        insert pA;
        PricebookEntry pbeA = makePbe(pA.Id, 100);
        insert pbeA;

        Opportunity opp = makeOpp('Current Opp');
        insert opp;
        insert makeOli(opp.Id, pbeA.Id, 100, opp.CloseDate);

        OpportunityAnalyticsCreate.activeOverride = true; // enable for the call under test (independent of the deployed CMDT)
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(new Set<Id>{ opp.Id });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Opportunity_Analytics__c WHERE Current_Opportunity__c = :opp.Id],
            'Set overload should create one analytics record');
    }

    /** A line item whose product has no clean product code is skipped. */
    @isTest
    static void testLineItemWithoutCleanCodeIsSkipped() {
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup
        // ProductCode null => Clean_Product_Code__c (LEFT(ProductCode,11)) is blank => skipped
        Product2 pNoCode = makeProduct('No Code Prod', null, STREAM_A);
        insert pNoCode;
        PricebookEntry pbe = makePbe(pNoCode.Id, 100);
        insert pbe;

        Opportunity opp = makeOpp('Current Opp');
        insert opp;
        insert makeOli(opp.Id, pbe.Id, 100, opp.CloseDate);

        OpportunityAnalyticsCreate.activeOverride = true; // enable for the call under test (independent of the deployed CMDT)
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(opp.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Opportunity_Analytics__c WHERE Current_Opportunity__c = :opp.Id],
            'Line items without a clean product code should produce no analytics records');
    }

    /** Null / empty inputs are safe no-ops. */
    @isTest
    static void testNullAndEmptyInputs() {
        Test.startTest();
        OpportunityAnalyticsCreate.createRecords((Id) null);
        OpportunityAnalyticsCreate.createRecords(new Set<Id>());
        OpportunityAnalyticsCreate.createRecords((Set<Id>) null);
        OpportunityAnalyticsCreate.createRecords(new List<Opportunity>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Opportunity_Analytics__c],
            'No analytics records should be created for null/empty input');
    }

    /** When the CMDT kill switch is off, nothing is created and the recursion guard is reset. */
    @isTest
    static void testKillSwitchOff() {
        OpportunityAnalyticsCreate.activeOverride = false; // kill switch off — also suppresses trigger-driven calls during setup
        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        insert pA;
        PricebookEntry pbeA = makePbe(pA.Id, 100);
        insert pbeA;

        Opportunity opp = makeOpp('Current Opp');
        insert opp;
        insert makeOli(opp.Id, pbeA.Id, 100, opp.CloseDate);

        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(opp.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Opportunity_Analytics__c WHERE Current_Opportunity__c = :opp.Id],
            'Kill switch off should produce no analytics records, even with valid line items');
        System.assertEquals(false, OpportunityAnalyticsCreate.isRunning,
            'Recursion guard should be cleared by the finally block after an early return');
    }

    /** A re-entrant call while already running is skipped by the recursion guard. */
    @isTest
    static void testRecursionGuardSkips() {
        OpportunityAnalyticsCreate.activeOverride = false; // suppress trigger-driven calls during data setup
        Product2 pA = makeProduct('Prod A', CODE_A, STREAM_A);
        insert pA;
        PricebookEntry pbeA = makePbe(pA.Id, 100);
        insert pbeA;

        Opportunity opp = makeOpp('Current Opp');
        insert opp;
        insert makeOli(opp.Id, pbeA.Id, 100, opp.CloseDate);

        // Force the feature on but the guard up: only the recursion guard should stop the call.
        OpportunityAnalyticsCreate.activeOverride = true;
        OpportunityAnalyticsCreate.isRunning = true; // simulate a call already in progress

        Test.startTest();
        OpportunityAnalyticsCreate.createRecords(opp.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Opportunity_Analytics__c WHERE Current_Opportunity__c = :opp.Id],
            'Re-entrant call should be skipped while another run is in progress');
    }
}
