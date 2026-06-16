@isTest
private class AccountPlanAgentServiceTest {

    @isTest
    static void summarizesPlan() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Agent Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology Intelligence', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        insert new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
            Node_Key__c = 'a', Node_Label__c = 'A', State__c = 'White_Space', Expected_Revenue__c = 120000,
            External_Key__c = plan.Id + '|' + fam.Id + '|a');
        insert new Plan_Signal__c(
            Account_Plan__c = plan.Id, Signal_Type__c = 'Expansion', Severity__c = 'High',
            Source__c = 'Whitespace_Cell', Summary__c = 'Gap crossed', Status__c = 'Open',
            Detected_Date__c = Date.today());

        AccountPlanAgentService.Request req = new AccountPlanAgentService.Request();
        req.planId = plan.Id;

        Test.startTest();
        List<AccountPlanAgentService.Response> res =
            AccountPlanAgentService.summarize(new List<AccountPlanAgentService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'one response');
        String s = res[0].summary;
        System.assert(s.contains('Agent Plan'), 'names the plan/firm: ' + s);
        System.assert(s.contains('owned ARR'), 'states owned ARR: ' + s);
        System.assert(s.contains('Lexology Intelligence'), 'names the top white-space family: ' + s);
        System.assert(s.contains('open signal'), 'mentions signals: ' + s);
    }

    @isTest
    static void handlesMissingPlan() {
        AccountPlanAgentService.Request r = new AccountPlanAgentService.Request(); // null planId
        List<AccountPlanAgentService.Response> res =
            AccountPlanAgentService.summarize(new List<AccountPlanAgentService.Request>{ r });
        System.assertEquals('No account plan specified.', res[0].summary, 'graceful on null');
    }
}
