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

        insert new Plan_Stakeholder__c(
            Account_Plan__c = plan.Id, Stakeholder_Name__c = 'Jane Doe', Role__c = 'GC',
            Influence__c = 'High', Sentiment__c = 'Champion', Buying_Center__c = 'Group Legal');

        insert new Plan_Objective__c(
            Account_Plan__c = plan.Id, Name = 'Land Intelligence', Status__c = 'In_Progress',
            Progress_Pct__c = 40, Target_Amount__c = 50000, Due_Date__c = Date.today().addDays(30),
            Linked_Family__c = famPro.Id);

        insert new Plan_Signal__c(
            Account_Plan__c = plan.Id, Signal_Type__c = 'Risk', Severity__c = 'High',
            Source__c = 'CPQ', Summary__c = 'Renewal window', Status__c = 'Open',
            Detected_Date__c = Date.today());

        insert new Plan_Team_Member__c(
            Account_Plan__c = plan.Id, User__c = UserInfo.getUserId(), Plan_Role__c = 'Plan_Lead');

        Test.startTest();
        AccountPlanController.PlanMatrix m = AccountPlanController.getMatrix(plan.Id);
        List<AccountPlanController.Stakeholder> stk = AccountPlanController.getStakeholders(plan.Id);
        List<AccountPlanController.Objective> objs = AccountPlanController.getObjectives(plan.Id);
        List<AccountPlanController.Signal> sigs = AccountPlanController.getSignals(plan.Id);
        List<AccountPlanController.TeamMember> team = AccountPlanController.getTeam(plan.Id);
        Test.stopTest();

        System.assertEquals(1, sigs.size(), 'one open signal');
        System.assertEquals('Risk', sigs[0].signalType, 'signal type');
        System.assertEquals(1, team.size(), 'one team member');
        System.assertEquals('Plan_Lead', team[0].role, 'team role');

        System.assertEquals('Test Plan', m.planName, 'plan name');
        System.assertEquals(1, m.cells.size(), 'one cell');
        System.assert(m.families.size() >= 1, 'at least one relevant family');
        System.assertEquals(100000, m.cells[0].arr, 'cell arr');

        System.assertEquals(1, stk.size(), 'one stakeholder');
        System.assertEquals('Champion', stk[0].sentiment, 'stakeholder sentiment');
        System.assertEquals('Jane Doe', stk[0].name, 'stakeholder name');

        System.assertEquals(1, objs.size(), 'one objective');
        System.assertEquals('Land Intelligence', objs[0].title, 'objective title');
        System.assertEquals(40, objs[0].progress, 'objective progress');
    }

    @isTest
    static void recalcHeadroomDelegatesToEngine() {
        System.assertEquals(0, AccountPlanController.recalcHeadroom(null), 'null plan is a no-op');

        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1,
            Benchmark_ARR_Per_Seat_Law_Firm__c = 1000);
        insert fam;

        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Recalc Plan', Plan_Tier__c = 'T1', SoW_Denominator__c = 50);
        insert plan;

        insert new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
            Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'london', Node_Label__c = 'London',
            State__c = 'White_Space', ARR__c = 0, External_Key__c = plan.Id + '|pro|london');

        Test.startTest();
        Integer changed = AccountPlanController.recalcHeadroom(plan.Id);
        Test.stopTest();

        System.assertEquals(1, changed, 'one white-space cell allocated');
        Whitespace_Cell__c c = [
            SELECT Expected_Revenue__c FROM Whitespace_Cell__c
            WHERE Account_Plan__c = :plan.Id LIMIT 1];
        System.assert(c.Expected_Revenue__c > 0, 'headroom allocated to the gap cell');
    }
}
