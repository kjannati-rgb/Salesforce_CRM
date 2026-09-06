@isTest
private class RenewalReconciliationSchedulable_Test {

    @isTest
    static void scheduleNightly_schedules_the_job() {
        Test.startTest();
        Id jobId = RenewalReconciliationSchedulable.scheduleNightly();
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(RenewalReconciliationSchedulable.NIGHTLY_CRON, ct.CronExpression,
            'scheduled with the nightly cron expression');
    }

    @isTest
    static void execute_runs_the_batch() {
        TestDataFactory.bypassAutomation();

        // Called directly rather than via System.schedule() + Test.stopTest(): a
        // Schedulable enqueuing a Batchable is two levels of async chaining, and only
        // the outer level is guaranteed to flush synchronously within one stopTest().
        // execute() itself is what Phase 3 needs covered - this exercises it directly.
        Test.startTest();
        new RenewalReconciliationSchedulable().execute(null);
        Test.stopTest();

        Integer runs = [SELECT COUNT() FROM Renewal_Run__c];
        Assert.isTrue(runs >= 1, 'execute() kicked off a reconciliation run');
    }
}
