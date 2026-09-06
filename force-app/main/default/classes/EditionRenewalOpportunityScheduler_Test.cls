@isTest
private class EditionRenewalOpportunityScheduler_Test {

    /**
     * PROD legitimately runs this job nightly already - System.schedule() throws if a job
     * with the same name is still scheduled, which test-context scheduling triggers too.
     * Aborting any pre-existing job first makes this test pass in both a clean org and PROD.
     */
    @isTest
    static void scheduleNightly_schedules_the_job() {
        for (CronTrigger existing : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Edition Renewal Opportunity Creation - Nightly']) {
            System.abortJob(existing.Id);
        }

        Test.startTest();
        Id jobId = EditionRenewalOpportunityScheduler.scheduleNightly();
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(EditionRenewalOpportunityScheduler.NIGHTLY_CRON, ct.CronExpression);
        Assert.areEqual('WAITING', ct.State);
    }

    @isTest
    static void execute_runs_the_batch() {
        Test.startTest();
        new EditionRenewalOpportunityScheduler().execute(null);
        Test.stopTest();

        Integer runs = [SELECT COUNT() FROM Renewal_Run__c WHERE Scope_Description__c LIKE 'Edition-based renewal%'];
        Assert.isTrue(runs > 0, 'scheduling the batch produces a Renewal_Run__c audit record');
    }
}
