@isTest
private class FirmRollupTriggerTest {

    @isTest static void opportunityTriggerInsertUpdateDeleteUndelete() {
        OpportunityAnalyticsCreate.activeOverride = false; // keep existing update-handler quiet
        Account firm = FirmRollupTestData.firm('TF');
        Account off = FirmRollupTestData.office('TO');

        Test.startTest();
        Opportunity opp = FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 100, 'GBP', Date.today());
        insert opp;                       // insert branch -> enqueue
        opp.Amount = 200; update opp;     // update branch (relevant change) -> enqueue
        delete opp;                       // delete branch -> enqueue
        Database.undelete(opp.Id, true);  // undelete branch -> enqueue
        Test.stopTest();                  // all enqueued queueables run; final state: opp present

        Account r = [SELECT Firm_Won_Count_AllTime__c FROM Account WHERE Id = :firm.Id];
        System.assertEquals(1, r.Firm_Won_Count_AllTime__c.intValue(), 'trigger path recomputed firm (count FX-independent)');
    }

    @isTest static void subscriptionTriggerEnqueues() {
        Account firm = FirmRollupTestData.firm('SF');
        Account off = FirmRollupTestData.office('SO');
        Date t = Date.today();

        Test.startTest();
        insert FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(-5), t.addDays(5), 100, 'GBP', null);
        Test.stopTest();

        Account r = [SELECT Firm_Active_Subscriptions__c FROM Account WHERE Id = :firm.Id];
        System.assertEquals(1, r.Firm_Active_Subscriptions__c.intValue(), 'subscription trigger recomputed firm');
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
