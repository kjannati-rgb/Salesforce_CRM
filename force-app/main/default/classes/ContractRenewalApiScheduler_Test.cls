@isTest
private class ContractRenewalApiScheduler_Test {

    @isTest
    static void scheduleNightly_schedules_the_job() {
        Test.startTest();
        Id jobId = ContractRenewalApiScheduler.scheduleNightly();
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(ContractRenewalApiScheduler.NIGHTLY_CRON, ct.CronExpression);
        Assert.areEqual('WAITING', ct.State);
    }

    @isTest
    static void execute_runs_the_batch() {
        Test.startTest();
        new ContractRenewalApiScheduler().execute(null);
        Test.stopTest();

        Integer runs = [SELECT COUNT() FROM Renewal_Run__c WHERE Scope_Description__c LIKE 'Contract renewal via SBQQ.RenewalAPI%'];
        Assert.isTrue(runs > 0, 'scheduling the batch produces a Renewal_Run__c audit record');
    }
}
