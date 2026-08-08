/**
 * Smoke test for TestDataFactory — proves every builder constructs valid records in
 * this org (so the factory itself can't silently rot and break downstream tests).
 */
@isTest
private class TestDataFactory_Test {
    @isTest
    static void builders_produce_valid_records() {
        Test.startTest();
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Opportunity o = TestDataFactory.opportunity(a.Id);
        Product2 p = TestDataFactory.product('TDF Law.com', 'TDFLAWM');
        PricebookEntry pbe = TestDataFactory.standardPbe(p.Id, 1000);
        SBQQ__Quote__c q = TestDataFactory.primaryQuote(a.Id, o.Id);
        SBQQ__QuoteLine__c ql = TestDataFactory.quoteLine(q.Id, p.Id, pbe.Id, 1000, 1);
        OpportunityLineItem oli = TestDataFactory.oli(o.Id, pbe.Id, 1000);
        Test.stopTest();

        Assert.isNotNull(a.Id, 'account');
        Assert.isNotNull(c.Id, 'contact');
        Assert.isNotNull(o.Id, 'opportunity');
        Assert.isNotNull(p.Id, 'product');
        Assert.isNotNull(pbe.Id, 'pricebook entry');
        Assert.isNotNull(q.Id, 'quote');
        Assert.isNotNull(ql.Id, 'quote line');
        Assert.isNotNull(oli.Id, 'opportunity line item');

        // the GBP determinism quirk: exchange rate resolves to 1
        Opportunity check = [SELECT CurrencyIsoCode FROM Opportunity WHERE Id = :o.Id];
        Assert.areEqual('GBP', check.CurrencyIsoCode, 'opp built in GBP for deterministic amounts');
    }
}
