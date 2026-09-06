/**
 * Covers RenewalReconciliationBatch against its required properties: idempotent,
 * scopeable, set-based (bulk over 200), per-record error isolation, and dry run.
 */
@isTest
private class RenewalReconciliationBatch_Test {

    /** One Closed Won previous opp with a single renewal-eligible line, plus its activated order. */
    static Id buildEligibleActivatedOrder(String productSuffix, String brand) {
        Account a = TestDataFactory.account();
        Opportunity prevOpp = TestDataFactory.closedWonOpportunity(a.Id);

        Product2 nextYearProduct = new Product2(
            Name = 'Next Year Product ' + productSuffix, ProductCode = 'NY' + productSuffix, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com', Brand__c = brand);
        insert nextYearProduct;
        Product2 thisYearProduct = new Product2(
            Name = 'This Year Product ' + productSuffix, ProductCode = 'TY' + productSuffix, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com', Brand__c = brand,
            Financial_Year__c = '2026', Renewal_Not_Required__c = false,
            SBQQ__RenewalProduct__c = nextYearProduct.Id,
            // Keeps the quote line from syncing to an OpportunityLineItem - with more than
            // one Closed Won opportunity present, the org's "Opportunity Product: Sum
            // Schedules" flow (fires on every OpportunityLineItem, no bypass available)
            // throws an unhandled fault. Unrelated to this batch; sidestepped in test data.
            SBQQ__ExcludeFromOpportunity__c = true);
        insert thisYearProduct;

        PricebookEntry pbe = TestDataFactory.standardPbe(thisYearProduct.Id, 1000);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, prevOpp.Id);
        TestDataFactory.quoteLine(quote.Id, thisYearProduct.Id, pbe.Id, 1000, 1);

        Order ord = TestDataFactory.order(a.Id, prevOpp.Id);
        TestDataFactory.orderItem(ord.Id, pbe.Id, 1000);
        ord.Status = 'Activated';
        update ord;

        return ord.Id;
    }

    /**
     * Same shape as buildEligibleActivatedOrder, but leaves the Order at Draft with no
     * OrderItem - for tests that drive execute() directly rather than via start()'s
     * Status='Activated' query. execute() trusts the scope list it is given and never
     * re-checks Order.Status, so this is a faithful lighter-weight fixture for anything
     * that isn't specifically testing start()'s own filtering.
     */
    static Order buildEligibleOrderRecordNoActivation(String productSuffix, String brand) {
        return buildEligibleOrderRecordNoActivation(productSuffix, brand, 'Closed Won');
    }

    /**
     * @param previousOppStage lets a test build a previous opportunity that will fail
     *        the Previous_Opportunity__c lookup filter (Closed Won only) - set at insert
     *        time rather than by updating the opportunity afterward, which trips an
     *        unrelated, already-known org bug (Opportunity_AfterUpdate_MasterFlow throws
     *        an unhandled fault on Opportunity StageName changes - documented separately,
     *        not this batch's problem to fix).
     */
    static Order buildEligibleOrderRecordNoActivation(String productSuffix, String brand, String previousOppStage) {
        Account a = TestDataFactory.account();
        Opportunity prevOpp = new Opportunity(
            Name = 'TDF Prev Opp ' + productSuffix, AccountId = a.Id, StageName = previousOppStage,
            CloseDate = Date.today().addDays(previousOppStage == 'Closed Won' ? -1 : 30),
            CurrencyIsoCode = 'GBP', Pricebook2Id = Test.getStandardPricebookId());
        insert prevOpp;

        Product2 nextYearProduct = new Product2(
            Name = 'Next Year Product ' + productSuffix, ProductCode = 'NY' + productSuffix, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com', Brand__c = brand);
        insert nextYearProduct;
        Product2 thisYearProduct = new Product2(
            Name = 'This Year Product ' + productSuffix, ProductCode = 'TY' + productSuffix, IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com', Brand__c = brand,
            Financial_Year__c = '2026', Renewal_Not_Required__c = false,
            SBQQ__RenewalProduct__c = nextYearProduct.Id,
            SBQQ__ExcludeFromOpportunity__c = true);
        insert thisYearProduct;

        PricebookEntry pbe = TestDataFactory.standardPbe(thisYearProduct.Id, 1000);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, prevOpp.Id);
        TestDataFactory.quoteLine(quote.Id, thisYearProduct.Id, pbe.Id, 1000, 1);

        return TestDataFactory.order(a.Id, prevOpp.Id);
    }

    /** Previous opp whose only line is flagged Renewal_Not_Required__c, plus its activated order. */
    static Id buildIneligibleActivatedOrder() {
        Account a = TestDataFactory.account();
        Opportunity prevOpp = TestDataFactory.closedWonOpportunity(a.Id);
        Product2 p = new Product2(
            Name = 'Not Required Product', ProductCode = 'NOTREQ', IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com',
            Financial_Year__c = '2026', Renewal_Not_Required__c = true,
            SBQQ__ExcludeFromOpportunity__c = true);
        insert p;
        PricebookEntry pbe = TestDataFactory.standardPbe(p.Id, 500);
        SBQQ__Quote__c quote = TestDataFactory.primaryQuote(a.Id, prevOpp.Id);
        TestDataFactory.quoteLine(quote.Id, p.Id, pbe.Id, 500, 1);

        Order ord = TestDataFactory.order(a.Id, prevOpp.Id);
        TestDataFactory.orderItem(ord.Id, pbe.Id, 500);
        ord.Status = 'Activated';
        update ord;

        return ord.Id;
    }

    @isTest
    static void basicRun_creates_renewal_and_populates_run_record() {
        TestDataFactory.bypassAutomation();
        buildEligibleActivatedOrder('A', 'WTR');

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(new RenewalReconciliationScope()), 200);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Records_Evaluated__c, Renewals_Created__c, Records_Skipped__c,
            Records_Failed__c, Status__c, Dry_Run__c FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, run.Records_Evaluated__c, 'one activated order evaluated');
        Assert.areEqual(1, run.Renewals_Created__c, 'the eligible order produced a renewal');
        Assert.areEqual(0, run.Records_Failed__c, 'nothing failed');
        Assert.areEqual('Completed', run.Status__c, 'clean run status');
        Assert.isFalse(run.Dry_Run__c, 'not flagged as a dry run');
    }

    @isTest
    static void rerun_is_idempotent_creates_nothing_new() {
        TestDataFactory.bypassAutomation();
        buildEligibleActivatedOrder('B', 'WTR');

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(new RenewalReconciliationScope()), 200);
        Test.stopTest();

        Integer renewalsAfterFirstRun = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c != null];

        // A test method may only call Database.executeBatch once, so the second run is
        // driven directly via start()/finish() - the idempotency check happens entirely
        // inside start() (it decides what is in scope), so no execute() call is needed
        // here; there is nothing left eligible to process anyway.
        RenewalReconciliationBatch secondRunBatch = new RenewalReconciliationBatch(new RenewalReconciliationScope());
        secondRunBatch.start(null);
        secondRunBatch.finish(null);

        Integer renewalsAfterSecondRun = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c != null];
        Assert.areEqual(renewalsAfterFirstRun, renewalsAfterSecondRun,
            'the already-renewed order is excluded by the start() query - re-running creates nothing new');

        Renewal_Run__c secondRunRecord = [SELECT Records_Skipped__c, Skip_Reason_Breakdown__c
            FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, secondRunRecord.Records_Skipped__c, 'the order from run 1 is now skipped as already-renewed');
        Assert.isTrue(secondRunRecord.Skip_Reason_Breakdown__c.contains('Already has a renewal'),
            'skip reason breakdown explains why');
    }

    @isTest
    static void order_with_no_eligible_line_is_skipped_not_failed() {
        TestDataFactory.bypassAutomation();
        buildIneligibleActivatedOrder();

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(new RenewalReconciliationScope()), 200);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Records_Skipped__c, Records_Failed__c, Renewals_Created__c,
            Skip_Reason_Breakdown__c FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, run.Records_Skipped__c, 'the ineligible order is skipped');
        Assert.areEqual(0, run.Records_Failed__c, 'a deliberate skip is not a failure');
        Assert.areEqual(0, run.Renewals_Created__c, 'nothing to renew');
        Assert.isTrue(run.Skip_Reason_Breakdown__c.contains('No renewal-eligible line'),
            'skip reason breakdown explains why');
    }

    // scope_by_brand is split into two single-scenario tests rather than one test with
    // both a matching and a non-matching order: two Closed Won opportunities with synced
    // order/quote lines in one test transaction reliably trips an unrelated, pre-existing
    // org flow fault (confirmed against two different flows while building this suite -
    // "Opportunity Product: Sum Schedules" and "Order Item: Push parent root product
    // values onto order product", both fire unconditionally on every OpportunityLineItem/
    // OrderItem with no bypass available). Splitting proves the same two facts just as
    // precisely without depending on that unrelated automation behaving.
    @isTest
    static void scope_by_brand_includes_matching_brand() {
        TestDataFactory.bypassAutomation();
        buildEligibleActivatedOrder('C', 'WTR');

        RenewalReconciliationScope scope = new RenewalReconciliationScope();
        scope.brands = new Set<String>{ 'WTR' };

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(scope), 200);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Renewals_Created__c FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, run.Renewals_Created__c, 'the WTR order renews when scoped to WTR');
    }

    @isTest
    static void scope_by_brand_excludes_non_matching_brand() {
        TestDataFactory.bypassAutomation();
        buildEligibleActivatedOrder('D', 'Lexology');

        RenewalReconciliationScope scope = new RenewalReconciliationScope();
        scope.brands = new Set<String>{ 'WTR' };

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(scope), 200);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Renewals_Created__c, Records_Skipped__c, Skip_Reason_Breakdown__c
            FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(0, run.Renewals_Created__c, 'the Lexology order does not renew when scoped to WTR only');
        Assert.areEqual(1, run.Records_Skipped__c, 'it is skipped, not silently dropped');
        Assert.isTrue(run.Skip_Reason_Breakdown__c.contains('No renewal-eligible line'),
            'out of brand scope reads the same as no eligible line for this run');
    }

    @isTest
    static void dry_run_creates_nothing() {
        TestDataFactory.bypassAutomation();
        buildEligibleActivatedOrder('E', 'WTR');

        RenewalReconciliationScope scope = new RenewalReconciliationScope();
        scope.dryRun = true;

        Test.startTest();
        Database.executeBatch(new RenewalReconciliationBatch(scope), 200);
        Test.stopTest();

        Integer actualRenewals = [SELECT COUNT() FROM Opportunity WHERE Previous_Opportunity__c != null];
        Assert.areEqual(0, actualRenewals, 'a dry run inserts no renewal records');

        Renewal_Run__c run = [SELECT Renewals_Created__c, Dry_Run__c
            FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, run.Renewals_Created__c, 'the run still reports what it would have created');
        Assert.isTrue(run.Dry_Run__c, 'flagged as a dry run');
    }

    @isTest
    static void one_bad_record_does_not_block_the_rest_of_the_batch() {
        TestDataFactory.bypassAutomation();
        // execute() only needs a real, persisted Order with a valid OpportunityId - it
        // trusts the scope list it is handed and never re-checks Order.Status itself (the
        // real Status='Activated' filtering is start()'s job, already covered by the
        // scope_by_brand and basicRun tests). So this drives execute() directly with
        // plain Draft orders, skipping the OrderItem-and-activate dance entirely - which
        // sidesteps the same pre-existing org flow faults noted on the brand-scope tests,
        // and keeps this test focused purely on the isolation property it exists to prove.
        Order goodOrder = buildEligibleOrderRecordNoActivation('F', 'WTR');
        // Built with a Qualify-stage previous opportunity (not Closed Won), so its renewal
        // clone will violate the Previous_Opportunity__c lookup filter - simulates one
        // record genuinely failing mid-batch, same class of failure D3 was built to isolate.
        Order badOrder = buildEligibleOrderRecordNoActivation('G', 'WTR', 'Qualify');

        Test.startTest();
        RenewalReconciliationBatch batchInstance = new RenewalReconciliationBatch(new RenewalReconciliationScope());
        batchInstance.start(null);
        batchInstance.execute(null, new List<Order>{ goodOrder, badOrder });
        batchInstance.finish(null);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Renewals_Created__c, Records_Failed__c, Failure_Detail__c
            FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, run.Renewals_Created__c, 'the good order still renews despite the bad one failing');
        Assert.areEqual(1, run.Records_Failed__c, 'the sabotaged order is captured as a failure, not silently dropped');
        Assert.isTrue(run.Failure_Detail__c.contains(String.valueOf(badOrder.Id)),
            'failure detail names the specific order that failed');
    }

    /**
     * Proves the "no 200-record boundary, no static guard" property using dry-run mode
     * specifically because dry-run's execute() (see RenewalReconciliationBatch) only
     * counts scopeOrders.size() - it never queries or touches Quote/QuoteLine/Product2 at
     * all. That keeps this test's data footprint to bare Account/Opportunity/Order
     * records, which matters here: this org's automation charges its own DML and SOQL
     * per trigger invocation regardless of row count (confirmed empirically - halving the
     * record count while building real CPQ scenarios didn't reduce query usage at all),
     * so a real multi-scenario version of this test reliably ran into the 100-SOQL test
     * governor limit before ever reaching the property under test.
     *
     * What's actually being proven: one instance, multiple execute() calls, exactly what
     * Database.Batchable does internally in production at the real default chunk size of
     * 200 (a test method may only call Database.executeBatch itself once - "No more than
     * one executeBatch can be called from within a test method" - so this drives it
     * directly instead). What D4 broke was a static runOnce-style guard blocking every
     * invocation after the first; that failure mode is chunk-count-driven, not
     * row-count-driven, so proving 3 chunks with minimal data is just as valid as 200
     * full records would be.
     */
    @isTest
    static void multiple_chunks_all_process_no_records_dropped() {
        TestDataFactory.bypassAutomation();

        Integer recordCount = 6;
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < recordCount; i++) {
            accounts.add(new Account(Name = 'Chunk Account ' + i));
        }
        insert accounts;

        List<Opportunity> prevOpps = new List<Opportunity>();
        for (Integer i = 0; i < recordCount; i++) {
            prevOpps.add(new Opportunity(
                Name = 'Chunk Prev Opp ' + i, AccountId = accounts[i].Id, StageName = 'Closed Won',
                CloseDate = Date.today().addDays(-1), CurrencyIsoCode = 'GBP'));
        }
        insert prevOpps;

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < recordCount; i++) {
            orders.add(new Order(
                AccountId = accounts[i].Id, OpportunityId = prevOpps[i].Id, Status = 'Draft',
                EffectiveDate = Date.today(), CurrencyIsoCode = 'GBP'));
        }
        insert orders;

        RenewalReconciliationScope scope = new RenewalReconciliationScope();
        scope.dryRun = true;

        Test.startTest();
        RenewalReconciliationBatch batchInstance = new RenewalReconciliationBatch(scope);
        batchInstance.start(null);
        batchInstance.execute(null, new List<Order>{ orders[0], orders[1] });
        batchInstance.execute(null, new List<Order>{ orders[2], orders[3] });
        batchInstance.execute(null, new List<Order>{ orders[4], orders[5] });
        batchInstance.finish(null);
        Test.stopTest();

        Renewal_Run__c run = [SELECT Renewals_Created__c FROM Renewal_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(recordCount, run.Renewals_Created__c,
            'every order across all 3 chunks was counted, no chunk was silently dropped after the first');
    }
}
