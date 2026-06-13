/**
 * TestDataFactory — Centellic Phase B foundation. Reusable test-data builders that
 * encode this org's specific quirks so every one of the 68 untested custom classes
 * can be covered efficiently (and correctly) rather than each test re-discovering them.
 *
 * Quirks baked in (learned the hard way):
 *  - Product2.Reporting_Stream__c is a REQUIRED dependent picklist controlled by Division__c;
 *    'ALM' / 'Subs - Law.com' is a valid pair.
 *  - The org-standard automation bypass is Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c
 *    (hierarchy custom setting). bypassAutomation() sets it so heavy triggers/flows don't fire in setup.
 *  - GBP makes Opportunity.Exchange_Rate__c (a formula) resolve to 1, so amounts are deterministic.
 *
 * Marked @isTest so it loads only in test context and needs no coverage of its own.
 */
@isTest
public class TestDataFactory {

    /**
     * Set the org-default automation bypass so data setup doesn't trip heavy automation.
     * Both flags matter: the flow bypass silences autolaunched flows; the validation-rule
     * bypass silences VRs/before-save validations (e.g. the "Ultimate Account" requirement
     * on Opportunity) that would otherwise block test-data inserts.
     */
    public static void bypassAutomation() {
        upsert new Application_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true,
            Disable_Validation_Rules__c = true);
    }

    public static Account account() {
        Account a = new Account(Name = 'TDF Account');
        insert a;
        return a;
    }

    public static Contact contact(Id accountId) {
        Contact c = new Contact(LastName = 'TDF Contact', AccountId = accountId);
        insert c;
        return c;
    }

    /** Opportunity in GBP (deterministic exchange rate), open stage. */
    public static Opportunity opportunity(Id accountId) {
        Opportunity o = new Opportunity(
            Name = 'TDF Opp',
            AccountId = accountId,
            StageName = 'Qualify',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = 'GBP');
        insert o;
        return o;
    }

    /** Active product with the valid Division/Reporting_Stream dependent-picklist pair. */
    public static Product2 product(String name, String productCode) {
        Product2 p = new Product2(
            Name = name,
            ProductCode = productCode,
            IsActive = true,
            Division__c = 'ALM',
            Reporting_Stream__c = 'Subs - Law.com');
        insert p;
        return p;
    }

    /** Standard-pricebook entry (GBP). Activates the standard pricebook id automatically. */
    public static PricebookEntry standardPbe(Id product2Id, Decimal unitPrice) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product2Id,
            UnitPrice = unitPrice,
            IsActive = true,
            CurrencyIsoCode = 'GBP');
        insert pbe;
        return pbe;
    }

    /** Primary CPQ quote on an opportunity (standard pricebook, GBP, 12-month term). */
    public static SBQQ__Quote__c primaryQuote(Id accountId, Id opportunityId) {
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Account__c = accountId,
            SBQQ__Opportunity2__c = opportunityId,
            SBQQ__Primary__c = true,
            SBQQ__PriceBook__c = Test.getStandardPricebookId(),
            SBQQ__PricebookId__c = Test.getStandardPricebookId(),
            CurrencyIsoCode = 'GBP',
            SBQQ__StartDate__c = Date.today(),
            SBQQ__SubscriptionTerm__c = 12);
        insert q;
        return q;
    }

    /** Quote line on a quote (price fields set consistently). */
    public static SBQQ__QuoteLine__c quoteLine(Id quoteId, Id product2Id, Id pbeId, Decimal price, Integer lineNumber) {
        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = product2Id,
            SBQQ__Quantity__c = 1,
            SBQQ__PricebookEntryId__c = pbeId,
            SBQQ__ListPrice__c = price,
            SBQQ__CustomerPrice__c = price,
            SBQQ__NetPrice__c = price,
            SBQQ__Number__c = lineNumber);
        insert ql;
        return ql;
    }

    public static OpportunityLineItem oli(Id opportunityId, Id pbeId, Decimal price) {
        OpportunityLineItem o = new OpportunityLineItem(
            OpportunityId = opportunityId,
            PricebookEntryId = pbeId,
            Quantity = 1,
            UnitPrice = price);
        insert o;
        return o;
    }
}
