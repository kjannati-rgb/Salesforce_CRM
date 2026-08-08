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
        bypassOrgAutomation();
    }

    /** Disable the org's validation rules + autolaunch flows + process builders for the RUNNING
     *  USER (user-level custom setting takes precedence over org/profile defaults) so Closed-Won
     *  opps can be seeded without the contact-role gate or Ultimate_Account__c re-stamping. */
    public static void bypassOrgAutomation() {
        List<Application_Settings__c> existing =
            [SELECT Id FROM Application_Settings__c WHERE SetupOwnerId = :UserInfo.getUserId()];
        Application_Settings__c s = existing.isEmpty()
            ? new Application_Settings__c(SetupOwnerId = UserInfo.getUserId())
            : existing[0];
        s.Disable_Validation_Rules__c = true;
        s.Disable_Autolaunch_Lightning_Flow__c = true;
        s.Disable_Process_Builders__c = true;
        upsert s;
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

    static Map<String, Id> pbeCache = new Map<String, Id>();
    /**
     * Existing standard PricebookEntry for (Family, Product Type 1, currency). Reuses the live
     * product catalog so tests don't have to satisfy Product2's required, Family-dependent
     * Reporting_Stream__c picklist. REQUIRES the calling test method to be @isTest(SeeAllData=true).
     */
    public static Id pbeFor(String family, String ptype, String iso) {
        String key = family + '|' + ptype + '|' + iso;
        if (pbeCache.containsKey(key)) return pbeCache.get(key);
        String soql = 'SELECT Id FROM PricebookEntry WHERE Pricebook2.IsStandard = true AND IsActive = true '
            + 'AND CurrencyIsoCode = :iso AND Product2.Family = :family '
            + (ptype == null ? 'AND Product2.Product_Type__c = null ' : 'AND Product2.Product_Type__c = :ptype ')
            + 'LIMIT 1';
        List<PricebookEntry> pbes = Database.query(soql);
        Id id = pbes.isEmpty() ? null : pbes[0].Id;
        pbeCache.put(key, id);
        return id;
    }

    public static OpportunityLineItem lineFromPbe(Id oppId, Id pbeId, Decimal total) {
        return new OpportunityLineItem(OpportunityId = oppId, PricebookEntryId = pbeId, Quantity = 1, UnitPrice = total);
    }

    public static Opportunity newOpp(Id firmId, Id officeId, String stage, String type,
                                     Decimal amount, String iso, Date close) {
        return new Opportunity(Name = 'OPP ' + stage, StageName = stage, CloseDate = close,
            Amount = amount, Type = type, Ultimate_Account__c = firmId, AccountId = officeId,
            CurrencyIsoCode = iso, Pricebook2Id = Test.getStandardPricebookId());
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
