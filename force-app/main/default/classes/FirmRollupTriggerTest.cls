@isTest
private class FirmRollupTriggerTest {

    @isTest static void opportunityTriggerInsertUpdateDeleteUndelete() {
        OpportunityAnalyticsCreate.activeOverride = false; // keep existing update-handler quiet
        FirmRollupTestData.bypassOrgAutomation();
        Account firm = FirmRollupTestData.firm('TF');
        Account off = FirmRollupTestData.office('TO');

        Test.startTest();
        Opportunity won = FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 100, 'GBP', Date.today());
        insert won;                       // insert branch -> enqueue
        won.Amount = 200; update won;     // update branch (relevant change) -> enqueue
        // delete/undelete on a non-won opp (Closed Won opps are delete-protected in this org)
        Opportunity open = FirmRollupTestData.newOpp(firm.Id, off.Id, 'Qualify', 'New Business', 50, 'GBP', Date.today());
        insert open;
        delete open;                      // delete branch -> enqueue
        Database.undelete(open.Id, true); // undelete branch -> enqueue
        Test.stopTest();

        Account r = [SELECT Firm_Won_Count_AllTime__c FROM Account WHERE Id = :firm.Id];
        System.assertEquals(1, r.Firm_Won_Count_AllTime__c.intValue(), 'one Closed Won counted (Qualify excluded)');
    }

    @isTest static void subscriptionTriggerEnqueues() {
        Account firm = FirmRollupTestData.firm('SF');
        Account off = FirmRollupTestData.office('SO');
        Date t = Date.today();

        Test.startTest();
        SBQQ__Subscription__c s = FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(-5), t.addDays(5), 100, 'GBP', null);
        insert s;                              // insert branch
        s.SBQQ__NetPrice__c = 200; update s;   // update branch (relevant change)
        delete s;                              // delete branch
        Database.undelete(s.Id, true);         // undelete branch
        Test.stopTest();

        Account r = [SELECT Firm_Active_Subscriptions__c FROM Account WHERE Id = :firm.Id];
        System.assertEquals(1, r.Firm_Active_Subscriptions__c.intValue(), 'subscription trigger recomputed firm across ins/upd/del/undel');
    }

    @isTest static void recursionGuardAndBypass() {
        FirmRollupService.isRunning = true;
        System.assert(FirmRollupTriggerGuard.isSuppressed(), 'suppressed while service running');
        // suppressed -> helpers early-return without error
        OpportunityFirmRollupHelper.handle(new List<Opportunity>(), null, false);
        SubscriptionFirmRollupHelper.handle(new List<SBQQ__Subscription__c>(), null, false);
        FirmRollupService.isRunning = false;

        FirmRollupTriggerGuard.bypass = true;
        System.assert(FirmRollupTriggerGuard.isSuppressed(), 'suppressed by bypass');
        FirmRollupTriggerGuard.bypass = false;
        System.assert(!FirmRollupTriggerGuard.isSuppressed(), 'not suppressed by default');

        // empty enqueue is a no-op
        OpportunityFirmRollupHelper.enqueue(new Set<Id>());
        OpportunityFirmRollupHelper.enqueue(null);
    }

    @isTest static void queueableChunking() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.bypassOrgAutomation();
        List<Id> firmIds = new List<Id>();
        Account off = FirmRollupTestData.office('QO');
        for (Integer i = 0; i < 3; i++) {
            Account f = FirmRollupTestData.firm('QF' + i);
            insert FirmRollupTestData.newOpp(f.Id, off.Id, 'Closed Won', 'New Business', 100, 'GBP', Date.today());
            firmIds.add(f.Id);
        }
        Test.startTest();
        System.enqueueJob(new FirmRollupQueueable(firmIds, 2)); // chunk 2 -> first 2 processed; no chaining in test
        Test.stopTest();

        Account r = [SELECT Firm_Won_Count_AllTime__c FROM Account WHERE Id = :firmIds[0]];
        System.assertEquals(1, r.Firm_Won_Count_AllTime__c.intValue(), 'first chunk firm processed');
    }
}
