@isTest
private class AccountPlanControllerTest {

    @isTest
    static void returnsMatrixForPlan() {
        Plan_Product_Family__c famPro = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Relevant_Corporate__c = true, Sort_Order__c = 1);
        Plan_Product_Family__c famAds = new Plan_Product_Family__c(
            Name = 'Advertising', Relevant_Law_Firm__c = true, Relevant_Corporate__c = false, Sort_Order__c = 6);
        insert new List<Plan_Product_Family__c>{ famPro, famAds };

        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Test Plan', Plan_Tier__c = 'T1', Deal_Model__c = 'Enterprise');
        insert plan;

        insert new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = famPro.Id,
            Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'london', Node_Label__c = 'London',
            State__c = 'Owned_Healthy', ARR__c = 100000, External_Key__c = plan.Id + '|' + famPro.Id + '|london');

        Test.startTest();
        AccountPlanController.PlanMatrix m = AccountPlanController.getMatrix(plan.Id);
        Test.stopTest();

        System.assertEquals('Test Plan', m.planName, 'plan name');
        System.assertEquals(1, m.cells.size(), 'one cell');
        System.assert(m.families.size() >= 1, 'at least one relevant family');
        System.assertEquals(100000, m.cells[0].arr, 'cell arr');
    }
}
