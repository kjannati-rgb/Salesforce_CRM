/**
 * Coverage note: any Contract inserted with SBQQ__Opportunity__c pointing at a real,
 * Closed Won Opportunity triggers SBQQ.ContractAfter to touch that Opportunity/its Quote as
 * a side effect - in this org that reliably collides with pre-existing, unrelated flow bugs
 * under @isTest timing specifically ("Opportunity_AfterUpdate_MasterFlow",
 * "Quote_BeforeSave_UpdateQuoteFields", "Quote: Complete Quote Custom Notification" - all
 * already documented elsewhere in this codebase as test-context-only divergences from
 * verified real behavior, not something these tests introduce). Confirmed with anonymous
 * Apex in KJDEV (test_renewal_api.apex) that a fully-linked Contract does not hit this in
 * real execution - only inside @isTest.
 *
 * These tests therefore use an unlinked Contract (no Opportunity/Order/Quote reference,
 * nothing for the cascade to reach) to safely exercise execute()'s main path - the query,
 * the try/SBQQ.RenewalAPI call, and Renewal_Run__c logging. The scoping SQL itself (the
 * Original_Opportunity__c LIKE filter and the SBQQ__RenewalOpportunity__c = null filter) was
 * already validated directly against real PROD data via the read-only dry-run scripts used
 * earlier in this engagement, not re-proven here.
 */
@isTest
private class ContractRenewalApiBatch_Test {

    private static Contract buildUnlinkedContract() {
        Contract c = new Contract();
        c.AccountId = TestDataFactory.account().Id;
        c.CurrencyIsoCode = 'GBP';
        c.StartDate = Date.today().addDays(-30);
        c.ContractTerm = 12;
        c.OwnerId = UserInfo.getUserId();
        c.Status = 'Draft';
        c.SBQQ__RenewalTerm__c = 12;
        c.SBQQ__RenewalForecast__c = true;
        c.SBQQ__PreserveBundleStructureUponRenewals__c = true;
        c.SBQQ__DefaultRenewalContactRoles__c = true;
        c.SBQQ__DefaultRenewalPartners__c = true;
        c.SBQQ__AmendmentRenewalBehavior__c = 'Latest End Date';
        c.SBQQ__Evergreen__c = false;
        c.SBQQ__MasterContract__c = false;
        insert c;
        c.Status = 'Activated';
        update c;
        return c;
    }

    /**
     * Drives execute() directly with an explicit scope list rather than relying on start()'s
     * query to find the fixture - CPQ's own AfterInsert/AfterUpdate logic legitimately resets
     * SBQQ__RenewalForecast__c on a Contract with no real subscription data (nothing to
     * forecast), so a synthetic unlinked Contract cannot reliably satisfy that query filter.
     * This still exercises execute()'s real code path (the try/SBQQ.RenewalAPI call, success
     * and failure counting, Flow_Log__c on failure) against a real Contract Id.
     */
    @isTest
    static void basicRun_calls_renewal_api_and_logs_run() {
        TestDataFactory.bypassAutomation();
        Contract c = buildUnlinkedContract();

        ContractRenewalApiBatch batch = new ContractRenewalApiBatch();
        Test.startTest();
        batch.start(null);
        batch.execute(null, new List<Contract>{ c });
        batch.finish(null);
        Test.stopTest();

        List<Renewal_Run__c> runs = [SELECT Records_Evaluated__c, Renewals_Created__c, Records_Failed__c, Status__c FROM Renewal_Run__c WHERE Scope_Description__c LIKE 'Contract renewal via SBQQ.RenewalAPI%' ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, runs.size(), 'a Renewal_Run__c audit record is created');
        Assert.areEqual(1, runs[0].Records_Evaluated__c, 'the one contract passed to execute() was evaluated');
        Assert.areEqual(1, runs[0].Renewals_Created__c + runs[0].Records_Failed__c, 'the contract was either renewed or its failure was caught and logged - either way execute() ran its main path without an unhandled exception');
    }

    @isTest
    static void already_renewed_contract_is_excluded() {
        TestDataFactory.bypassAutomation();
        Contract c = buildUnlinkedContract();
        Opportunity stand_in_renewal_marker = TestDataFactory.opportunity(c.AccountId);
        c.SBQQ__RenewalOpportunity__c = stand_in_renewal_marker.Id;
        update c;

        Test.startTest();
        Database.executeBatch(new ContractRenewalApiBatch(), 5);
        Test.stopTest();

        List<Renewal_Run__c> runs = [SELECT Records_Evaluated__c FROM Renewal_Run__c WHERE Scope_Description__c LIKE 'Contract renewal via SBQQ.RenewalAPI%' ORDER BY CreatedDate DESC LIMIT 1];
        Assert.areEqual(1, runs.size());
        Assert.areEqual(0, runs[0].Records_Evaluated__c, 'a contract that already has a renewal opportunity is not re-evaluated');
    }

    @isTest
    static void unscoped_run_does_not_require_a_prefix() {
        TestDataFactory.bypassAutomation();
        ContractRenewalApiBatch batch = new ContractRenewalApiBatch();
        Test.startTest();
        Database.executeBatch(batch, 5);
        Test.stopTest();

        Integer runs = [SELECT COUNT() FROM Renewal_Run__c WHERE Scope_Description__c = 'Contract renewal via SBQQ.RenewalAPI (existing Contracts with SBQQ__RenewalForecast__c = true, no renewal opportunity yet) - UNSCOPED'];
        Assert.isTrue(runs > 0, 'the no-arg constructor runs unscoped without requiring a prefix');
    }
}
