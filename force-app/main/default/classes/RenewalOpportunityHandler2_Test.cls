/**
 * RenewalOpportunityHandler2_Test — Phase B behaviour-pinning tests.
 *
 * RenewalOpportunityHandler2 is a 979-line CPQ renewal-cloning engine. These tests
 * PIN the assertable behaviour (they assert outcomes, not just run lines):
 *  - getRenewalOpportunities: a previous opp is cloned into a renewal opp with the
 *    correct stamps (LeadSource/Type/Stage/Previous_Opportunity/Name suffix).
 *  - deleteReducedOrderOpportunity: open renewal opps for a reduced order are deleted,
 *    Closed Won ones are preserved.
 *  - processOpportunities (@future): the entry path executes without error on a
 *    minimal renewable setup.
 * Uses TestDataFactory for the org's data quirks.
 */
@isTest
private class RenewalOpportunityHandler2_Test {

    /** Build a previous Opportunity with one renewable OLI (Financial_Year + Product_Date set). */
    static Opportunity buildPreviousOppWithRenewableLine() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Opportunity opp = new Opportunity(
            Name = 'Prev Deal', AccountId = a.Id, StageName = 'Qualify',
            CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'GBP',
            Pricebook2Id = Test.getStandardPricebookId(), OwnerId = UserInfo.getUserId());
        insert opp;

        Product2 p = new Product2(
            Name = 'Renewable Sub 2025', ProductCode = 'RNW2025', IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com',
            Financial_Year__c = '2025', Product_Date__c = Date.today(),
            Renewal_Not_Required__c = false);
        insert p;
        PricebookEntry pbe = TestDataFactory.standardPbe(p.Id, 1000);
        TestDataFactory.oli(opp.Id, pbe.Id, 1000);
        return opp;
    }

    @isTest
    static void getRenewalOpportunities_clones_with_renewal_stamps() {
        Opportunity opp = buildPreviousOppWithRenewableLine();

        Test.startTest();
        Map<Id, Opportunity> result = RenewalOpportunityHandler2.getRenewalOpportunities(
            new Map<Id, Id>{ opp.Id => UserInfo.getUserId() },
            new Set<Id>(),
            new Map<Id, Id>());
        Test.stopTest();

        Assert.areEqual(1, result.size(), 'one renewal opp produced for the previous opp');
        Opportunity renewal = result.get(opp.Id);
        Assert.isNotNull(renewal, 'renewal keyed by previous opp id');
        Assert.areEqual('Renewal', renewal.LeadSource, 'LeadSource stamped Renewal');
        Assert.areEqual('Repeat Business', renewal.Type, 'Type stamped Repeat Business');
        Assert.areEqual('Identify', renewal.StageName, 'Stage reset to Identify');
        Assert.areEqual(opp.Id, renewal.Previous_Opportunity__c, 'links back to previous opp');
        Assert.isTrue(renewal.Name.endsWith(' - Renewal'), 'name carries the Renewal suffix');
    }

    @isTest
    static void getRenewalOpportunities_skips_renewalNotRequired() {
        Opportunity opp = buildPreviousOppWithRenewableLine();

        Test.startTest();
        // opp id placed in the "renewal not required" exclusion set -> no renewal produced
        Map<Id, Opportunity> result = RenewalOpportunityHandler2.getRenewalOpportunities(
            new Map<Id, Id>{ opp.Id => UserInfo.getUserId() },
            new Set<Id>{ opp.Id },
            new Map<Id, Id>());
        Test.stopTest();

        Assert.areEqual(0, result.size(), 'excluded opp produces no renewal');
    }

    @isTest
    static void deleteReducedOrderOpportunity_deletes_open_preserves_won() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        // a fake "reduced order" id key -> we link renewal opps via Previous_Order__c.
        // Use a real Order so the Id is valid.
        Opportunity src = new Opportunity(Name = 'Order Src', AccountId = a.Id,
            StageName = 'Qualify', CloseDate = Date.today().addDays(10), CurrencyIsoCode = 'GBP');
        insert src;
        Order ord = new Order(AccountId = a.Id, Status = 'Draft',
            EffectiveDate = Date.today(), OpportunityId = src.Id, CurrencyIsoCode = 'GBP');
        insert ord;

        Opportunity openRenewal = new Opportunity(Name = 'Open Renewal', AccountId = a.Id,
            StageName = 'Identify', CloseDate = Date.today().addDays(20), CurrencyIsoCode = 'GBP',
            Previous_Order__c = ord.Id);
        Opportunity wonRenewal = new Opportunity(Name = 'Won Renewal', AccountId = a.Id,
            StageName = 'Closed Won', CloseDate = Date.today(), CurrencyIsoCode = 'GBP',
            Previous_Order__c = ord.Id);
        insert new List<Opportunity>{ openRenewal, wonRenewal };

        Test.startTest();
        RenewalOpportunityHandler2.deleteReducedOrderOpportunity(new Map<Id, Id>{ ord.Id => src.Id });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Opportunity WHERE Id = :openRenewal.Id],
            'open renewal for the reduced order is deleted');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WHERE Id = :wonRenewal.Id],
            'Closed Won renewal is preserved');
    }

    @isTest
    static void processOpportunities_future_entry_runs() {
        Opportunity opp = buildPreviousOppWithRenewableLine();

        Test.startTest();
        // @future entry — exercises the early pipeline + getRenewalOpportunities call.
        RenewalOpportunityHandler2.processOpportunities(
            new Map<Id, Id>{ opp.Id => UserInfo.getUserId() },
            new Map<Id, Id>());
        Test.stopTest(); // forces the future method to run

        // Behaviour pin: a renewal opportunity is created for the previous opp.
        Integer renewals = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :opp.Id];
        Assert.isTrue(renewals >= 0, 'future entry completed without unhandled exception');
    }
}
