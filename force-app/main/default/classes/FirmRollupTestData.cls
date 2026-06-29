/**
 * FSS test data factory. Injects deterministic FX rates + group map so behaviour assertions are
 * exact and independent of org rate/CMDT drift.  Test rates: GBP=1 (corp), USD=2, EUR=4, target USD
 * → GBP×2, EUR÷2, USD pass-through.  Dated table left empty so conversion is date-independent
 * (every lookup falls back to static), making Σgroup == firm net exact.
 */
@isTest
public class FirmRollupTestData {

    public static Id rt(String dev) {
        return Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(dev).getRecordTypeId();
    }

    /** Inject deterministic config; call at the top of each behaviour test. */
    public static void injectStandardConfig() {
        Map<String, Decimal> stat = new Map<String, Decimal>{ 'GBP' => 1, 'USD' => 2, 'EUR' => 4 };
        CurrencyConvUSD.loadForTest(stat, new Map<String, List<CurrencyConvUSD.DatedRate>>(), 'USD', 'Dated');
        FirmRollupService.setConfigForTest(1, stdGroupMap());
    }

    public static Map<String, String> stdGroupMap() {
        return new Map<String, String>{
            'Events||Sponsorship' => 'Events - Sponsorship',
            'Events||Ticket' => 'Events - Delegate Ticket',
            'Events||' => 'Events - Other',
            'Subs - Law.com||' => 'Law.com / ALM',
            'Subs - Lexology Pro||' => 'Lexology PRO & Intelligence',
            'Advertising||' => 'Advertising'
        };
    }

    public static Account firm(String name) {
        Account a = new Account(Name = name, RecordTypeId = rt('Firm'));
        insert a; return a;
    }
    public static Account office(String name) {
        Account a = new Account(Name = name, RecordTypeId = rt('Office'));
        insert a; return a;
    }

    public static Product2 product(String family, String ptype) {
        Product2 p = new Product2(Name = (family + '-' + (ptype == null ? 'def' : ptype)),
                                  Family = family, Product_Type__c = ptype, IsActive = true);
        insert p; return p;
    }

    static Map<String, Id> pbeCache = new Map<String, Id>();
    /** Standard PricebookEntry for product×currency (created once). */
    public static Id pbe(Id productId, String iso) {
        String key = productId + '|' + iso;
        if (pbeCache.containsKey(key)) return pbeCache.get(key);
        PricebookEntry e = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId, UnitPrice = 1, IsActive = true, CurrencyIsoCode = iso);
        insert e;
        pbeCache.put(key, e.Id);
        return e.Id;
    }

    public static Opportunity newOpp(Id firmId, Id officeId, String stage, String type,
                                     Decimal amount, String iso, Date close) {
        return new Opportunity(Name = 'OPP ' + stage, StageName = stage, CloseDate = close,
            Amount = amount, Type = type, Ultimate_Account__c = firmId, AccountId = officeId,
            CurrencyIsoCode = iso, Pricebook2Id = Test.getStandardPricebookId());
    }

    public static OpportunityLineItem line(Id oppId, Id productId, Decimal total, String iso) {
        // OLI CurrencyIsoCode is inherited from the parent Opportunity (not writeable);
        // currency is honoured via the matching-currency PricebookEntry.
        return new OpportunityLineItem(OpportunityId = oppId, PricebookEntryId = pbe(productId, iso),
            Quantity = 1, UnitPrice = total);
    }

    public static SBQQ__Subscription__c sub(Id firmId, Id officeId, Date startD, Date endD,
                                            Decimal net, String iso, Date terminated) {
        // SBQQ__StartDate__c / SBQQ__EndDate__c (queried by the engine) are formulas that derive
        // from the writeable SBQQ__SubscriptionStartDate__c / SBQQ__SubscriptionEndDate__c.
        return new SBQQ__Subscription__c(
            Ultimate_Parent__c = firmId, SBQQ__Account__c = officeId,
            SBQQ__SubscriptionStartDate__c = startD, SBQQ__SubscriptionEndDate__c = endD,
            SBQQ__NetPrice__c = net, SBQQ__Quantity__c = 1,
            SBQQ__TerminatedDate__c = terminated, CurrencyIsoCode = iso);
    }
}
