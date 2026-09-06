@isTest
private class EditionRenewalOpportunityBatch_Test {

    /**
     * Target renewal product with a standard-pricebook GBP entry, matching what an existing
     * catalogue product actually has. The one negative test that needs a product with no
     * pricebook entry builds its own Product2 directly rather than using this helper.
     */
    private static Product2 targetProduct(String name, String code, Date productDate) {
        Product2 p = new Product2(
            Name = name, ProductCode = code, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com',
            SBQQ__SubscriptionType__c = 'One-time', Product_Date__c = productDate,
            SBQQ__ExcludeFromOpportunity__c = true);
        insert p;
        TestDataFactory.standardPbe(p.Id, 1);
        return p;
    }

    private static Product2 sourceProduct(String name, String code, Id renewalProductId, String subscriptionType) {
        Product2 p = new Product2(
            Name = name, ProductCode = code, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com',
            Renewal_Not_Required__c = true, SBQQ__RenewalProduct__c = renewalProductId,
            SBQQ__SubscriptionType__c = subscriptionType,
            SBQQ__ExcludeFromOpportunity__c = true);
        insert p;
        return p;
    }

    /**
     * Builds a Closed Won source opportunity with a primary quote line on an edition-based,
     * Renewal_Not_Required__c product, plus its own Activated order - the exact shape this
     * batch's start() query targets, matching the real "WTR 1000 2026 - Biography" style
     * records this was reverse engineered from.
     */
    private static Opportunity buildEligibleSource(Contact contact, String suffix, Id renewalProductId, String subscriptionType, Decimal price) {
        return buildEligibleSource(contact, suffix, 'Edition Product ' + suffix, renewalProductId, subscriptionType, price);
    }

    private static Opportunity buildEligibleSource(Contact contact, String suffix, String sourceProductName, Id renewalProductId, String subscriptionType, Decimal price) {
        Account a = TestDataFactory.account();
        Opportunity opp = TestDataFactory.closedWonOpportunity(a.Id);
        opp.Primary_Contact__c = contact.Id;
        update opp;

        Product2 srcProduct = sourceProduct(sourceProductName, 'SRC' + suffix, renewalProductId, subscriptionType);
        PricebookEntry srcPbe = TestDataFactory.standardPbe(srcProduct.Id, price);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, opp.Id);
        TestDataFactory.quoteLine(quote.Id, srcProduct.Id, srcPbe.Id, price, 1);

        Order ord = TestDataFactory.order(a.Id, opp.Id);
        TestDataFactory.orderItem(ord.Id, srcPbe.Id, price);
        ord.Status = 'Activated';
        update ord;

        return opp;
    }

    @isTest
    static void basicRun_creates_successor_with_quote_and_line() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 target = targetProduct('Edition Product 2027 A', 'TGT-A', Date.today().addMonths(6));
        Opportunity source = buildEligibleSource(c, 'A', target.Id, 'One-time', 1000);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        List<Opportunity> successors = [
            SELECT Id, StageName, Type, LeadSource, Amount, Previous_Opportunity__c, Previous_Order__c
            FROM Opportunity WHERE Previous_Opportunity__c = :source.Id
        ];
        Assert.areEqual(1, successors.size(), 'exactly one successor opportunity is created');
        Assert.areEqual('Identify', successors[0].StageName, 'successor opens at Identify stage');
        Assert.areEqual('Repeat Business', successors[0].Type, 'successor is typed as Repeat Business');
        Assert.areEqual('Renewal', successors[0].LeadSource, 'successor lead source is Renewal');
        Assert.areEqual(1000, successors[0].Amount, 'amount rolls forward unchanged');
        Assert.isNotNull(successors[0].Previous_Order__c, 'previous order is populated from the source opp\'s activated order');

        List<SBQQ__Quote__c> quotes = [SELECT Id, SBQQ__Primary__c, SBQQ__Status__c FROM SBQQ__Quote__c WHERE SBQQ__Opportunity2__c = :successors[0].Id];
        Assert.areEqual(1, quotes.size(), 'a primary draft quote is created on the successor');
        Assert.isTrue(quotes[0].SBQQ__Primary__c);
        Assert.areEqual('Draft', quotes[0].SBQQ__Status__c);

        List<SBQQ__QuoteLine__c> lines = [SELECT SBQQ__Product__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quotes[0].Id];
        Assert.areEqual(1, lines.size(), 'a quote line on the mapped renewal product is created');
        Assert.areEqual(target.Id, lines[0].SBQQ__Product__c);

        List<OpportunityLineItem> olis = [SELECT Product2Id FROM OpportunityLineItem WHERE OpportunityId = :successors[0].Id];
        Assert.areEqual(1, olis.size(), 'a matching opportunity line item is created');
        Assert.areEqual(target.Id, olis[0].Product2Id);
    }

    @isTest
    static void idempotent_rerun_creates_no_duplicate() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 target = targetProduct('Edition Product 2027 B', 'TGT-B', Date.today().addMonths(6));
        Opportunity source = buildEligibleSource(c, 'B', target.Id, 'One-time', 500);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        Integer firstRunCount = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :source.Id];
        Assert.areEqual(1, firstRunCount, 'first run creates one successor');

        EditionRenewalOpportunityBatch secondRun = new EditionRenewalOpportunityBatch();
        Database.BatchableContext bc = null;
        secondRun.start(bc);
        List<SBQQ__QuoteLine__c> secondScope = [
            SELECT Id, SBQQ__Quote__c, SBQQ__Quantity__c, SBQQ__NetPrice__c, SBQQ__ListPrice__c,
                SBQQ__Quote__r.SBQQ__Opportunity2__c, SBQQ__Quote__r.SBQQ__Opportunity2__r.Name,
                SBQQ__Quote__r.SBQQ__Opportunity2__r.AccountId, SBQQ__Quote__r.SBQQ__Opportunity2__r.Account.Name,
                SBQQ__Quote__r.SBQQ__Opportunity2__r.OwnerId, SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode,
                SBQQ__Quote__r.SBQQ__Opportunity2__r.Pricebook2Id, SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__c,
                SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__r.Name,
                SBQQ__Quote__r.SBQQ__PriceBook__c, SBQQ__Quote__r.SBQQ__PricebookId__c,
                SBQQ__Product__c, SBQQ__Product__r.Name,
                SBQQ__Product__r.SBQQ__RenewalProduct__c, SBQQ__Product__r.SBQQ__RenewalProduct__r.Name,
                SBQQ__Product__r.SBQQ__RenewalProduct__r.Product_Date__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__r.SBQQ__Opportunity2__c = :source.Id
        ];
        secondRun.execute(bc, secondScope);
        secondRun.finish(bc);

        Integer secondRunCount = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :source.Id];
        Assert.areEqual(1, secondRunCount, 'a second run against the same source does not create a duplicate successor');
    }

    @isTest
    static void skips_renewable_subscription_type() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 target = targetProduct('Edition Product 2027 C', 'TGT-C', Date.today().addMonths(6));
        Opportunity source = buildEligibleSource(c, 'C', target.Id, 'Renewable', 750);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        Integer successors = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :source.Id];
        Assert.areEqual(0, successors, 'a Renewable-subscription-type line stays RenewalOpportunityHandler2\'s territory and is not touched here');
    }

    @isTest
    static void multi_line_source_creates_two_successors() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 targetFirm = targetProduct('Edition Product 2027 Firm', 'TGT-FIRM', Date.today().addMonths(6));
        Product2 targetBio = targetProduct('Edition Product 2027 Bio', 'TGT-BIO', Date.today().addMonths(6));

        Opportunity opp = TestDataFactory.closedWonOpportunity(a.Id);
        opp.Primary_Contact__c = c.Id;
        update opp;

        Product2 srcFirm = sourceProduct('Edition Product Firm', 'SRC-FIRM', targetFirm.Id, 'One-time');
        Product2 srcBio = sourceProduct('Edition Product Bio', 'SRC-BIO', targetBio.Id, 'One-time');
        PricebookEntry pbeFirm = TestDataFactory.standardPbe(srcFirm.Id, 1200);
        PricebookEntry pbeBio = TestDataFactory.standardPbe(srcBio.Id, 800);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, opp.Id);
        TestDataFactory.quoteLine(quote.Id, srcFirm.Id, pbeFirm.Id, 1200, 1);
        TestDataFactory.quoteLine(quote.Id, srcBio.Id, pbeBio.Id, 800, 2);

        Order ord = TestDataFactory.order(a.Id, opp.Id);
        TestDataFactory.orderItem(ord.Id, pbeFirm.Id, 1200);
        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        List<Opportunity> successors = [SELECT Id, Amount FROM Opportunity WHERE Previous_Opportunity__c = :opp.Id ORDER BY Amount DESC];
        Assert.areEqual(2, successors.size(), 'one successor per eligible source line, not one aggregated successor');
        Assert.areEqual(1200, successors[0].Amount);
        Assert.areEqual(800, successors[1].Amount);
    }

    @isTest
    static void missing_pricebook_entry_logs_failure_without_blocking_opportunity() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        // Target product with no PricebookEntry at all - the quote line step must fail
        // in isolation, without preventing the Opportunity itself from being created.
        Product2 target = new Product2(
            Name = 'Edition Product 2027 D', ProductCode = 'TGT-D', IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com',
            SBQQ__SubscriptionType__c = 'One-time', Product_Date__c = Date.today().addMonths(6),
            SBQQ__ExcludeFromOpportunity__c = true);
        insert target;
        Opportunity source = buildEligibleSource(c, 'D', target.Id, 'One-time', 600);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        List<Opportunity> successors = [SELECT Id FROM Opportunity WHERE Previous_Opportunity__c = :source.Id];
        Assert.areEqual(1, successors.size(), 'the opportunity is still created even though no pricebook entry exists for the renewal product');

        List<SBQQ__QuoteLine__c> lines = [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Opportunity2__c = :successors[0].Id];
        Assert.areEqual(0, lines.size(), 'no quote line is created when the pricebook entry is missing');

        Integer errorLogs = [SELECT COUNT() FROM Flow_Log__c WHERE Class_Name__c = 'EditionRenewalOpportunityBatch' AND CreatedDate = TODAY];
        Assert.isTrue(errorLogs > 0, 'the missing pricebook entry is logged rather than silently dropped');
    }

    /**
     * A PROD dry run found real Closed Won opportunities carrying a duplicate zero-value
     * quote line for the same product alongside the real priced line (a source data quality
     * issue, not something this batch should reproduce as a junk $0 pipeline entry).
     */
    @isTest
    static void zero_amount_line_is_skipped_not_created() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 target = targetProduct('Edition Product 2027 E', 'TGT-E', Date.today().addMonths(6));
        Opportunity source = buildEligibleSource(c, 'E', target.Id, 'One-time', 0);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        Integer successors = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :source.Id];
        Assert.areEqual(0, successors, 'a zero-amount source line does not produce a junk successor opportunity');
    }

    /**
     * Two quote lines on the same source opportunity mapping to the same renewal product
     * (a real duplicate-data scenario found in PROD) must produce exactly one successor,
     * not one per duplicate line.
     */
    /**
     * excludeProductNamePrefix is how the nightly scheduler now runs everything except
     * Lexology Index - a source line under the excluded prefix must be skipped even though it
     * otherwise meets every eligibility condition, while a source line outside it still gets
     * a successor.
     */
    @isTest
    static void exclude_prefix_skips_matching_family() {
        TestDataFactory.bypassAutomation();
        Contact c = TestDataFactory.contact(TestDataFactory.account().Id);
        Product2 targetExcluded = targetProduct('Lexology Index 2027 G', 'TGT-G', Date.today().addMonths(6));
        Opportunity excludedSource = buildEligibleSource(c, 'G', 'Lexology Index Arbitration G', targetExcluded.Id, 'One-time', 1100);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(null, 'Lexology Index'), 200);
        Test.stopTest();

        Integer excludedSuccessors = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :excludedSource.Id];
        Assert.areEqual(0, excludedSuccessors, 'a source line under the excluded product prefix is skipped');
    }

    @isTest
    static void exclude_prefix_does_not_skip_other_families() {
        TestDataFactory.bypassAutomation();
        Contact c = TestDataFactory.contact(TestDataFactory.account().Id);
        Product2 targetIncluded = targetProduct('IAM Patent 1000 2027 H', 'TGT-H', Date.today().addMonths(6));
        Opportunity includedSource = buildEligibleSource(c, 'H', 'IAM Patent 1000 Firm H', targetIncluded.Id, 'One-time', 1300);

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(null, 'Lexology Index'), 200);
        Test.stopTest();

        Integer includedSuccessors = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :includedSource.Id];
        Assert.areEqual(1, includedSuccessors, 'a source line outside the excluded prefix still gets a successor');
    }

    @isTest
    static void duplicate_lines_same_target_product_create_only_one_successor() {
        TestDataFactory.bypassAutomation();
        Account a = TestDataFactory.account();
        Contact c = TestDataFactory.contact(a.Id);
        Product2 target = targetProduct('Edition Product 2027 F', 'TGT-F', Date.today().addMonths(6));

        Opportunity opp = TestDataFactory.closedWonOpportunity(a.Id);
        opp.Primary_Contact__c = c.Id;
        update opp;

        Product2 srcProduct = sourceProduct('Edition Product F', 'SRC-F', target.Id, 'One-time');
        PricebookEntry srcPbe = TestDataFactory.standardPbe(srcProduct.Id, 900);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, opp.Id);
        TestDataFactory.quoteLine(quote.Id, srcProduct.Id, srcPbe.Id, 900, 1);
        TestDataFactory.quoteLine(quote.Id, srcProduct.Id, srcPbe.Id, 900, 2);

        Order ord = TestDataFactory.order(a.Id, opp.Id);
        TestDataFactory.orderItem(ord.Id, srcPbe.Id, 900);
        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        Database.executeBatch(new EditionRenewalOpportunityBatch(), 200);
        Test.stopTest();

        Integer successors = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c = :opp.Id];
        Assert.areEqual(1, successors, 'two duplicate source lines for the same target product create only one successor');
    }
}
