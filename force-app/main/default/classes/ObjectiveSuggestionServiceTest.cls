@isTest
private class ObjectiveSuggestionServiceTest {

    @isTest
    static void suggestsFromHeadroomAndSignalsThenDedupes() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Sug Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c famA = new Plan_Product_Family__c(
            Name = 'Fam A', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        Plan_Product_Family__c famB = new Plan_Product_Family__c(
            Name = 'Fam B', Relevant_Law_Firm__c = true, Sort_Order__c = 2);
        insert new List<Plan_Product_Family__c>{ famA, famB };

        insert new List<Whitespace_Cell__c>{
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = famA.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'a1', Node_Label__c = 'A1',
                State__c = 'White_Space', Expected_Revenue__c = 60000, External_Key__c = plan.Id + '|' + famA.Id + '|a1'),
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = famA.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'a2', Node_Label__c = 'A2',
                State__c = 'White_Space', Expected_Revenue__c = 40000, External_Key__c = plan.Id + '|' + famA.Id + '|a2'),
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = famB.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'b1', Node_Label__c = 'B1',
                State__c = 'White_Space', Expected_Revenue__c = 10000, External_Key__c = plan.Id + '|' + famB.Id + '|b1')
        };
        insert new Plan_Signal__c(Account_Plan__c = plan.Id, Signal_Type__c = 'Expansion',
            Severity__c = 'High', Source__c = 'Whitespace_Cell', Summary__c = 'White-space threshold crossed',
            Status__c = 'Open', Detected_Date__c = Date.today());

        Test.startTest();
        List<ObjectiveSuggestionService.Suggestion> sug = ObjectiveSuggestionService.suggest(plan.Id);
        Test.stopTest();

        Boolean hasFamA = false, hasSignal = false;
        Decimal famATarget = 0;
        for (ObjectiveSuggestionService.Suggestion s : sug) {
            if (s.source == 'Headroom' && s.linkedFamilyId == famA.Id) {
                hasFamA = true;
                famATarget = s.targetAmount;
            }
            if (s.source == 'Signal') hasSignal = true;
            System.assertNotEquals(famB.Id, s.linkedFamilyId, 'trivial Fam B headroom is below the floor');
        }
        System.assert(hasFamA, 'Fam A headroom suggested');
        System.assertEquals(100000, famATarget, 'headroom aggregated across nodes');
        System.assert(hasSignal, 'open expansion signal suggested');

        Id objId = ObjectiveSuggestionService.accept(plan.Id, 'Convert Fam A white space', 100000, famA.Id);
        Plan_Objective__c o = [
            SELECT Linked_Family__c, Target_Amount__c, Status__c FROM Plan_Objective__c WHERE Id = :objId];
        System.assertEquals(famA.Id, o.Linked_Family__c, 'objective linked to the family');
        System.assertEquals(100000, o.Target_Amount__c, 'target carried over');

        for (ObjectiveSuggestionService.Suggestion s : ObjectiveSuggestionService.suggest(plan.Id)) {
            System.assertNotEquals(famA.Id, s.linkedFamilyId, 'Fam A deduped once an objective covers it');
        }
    }

    @isTest
    static void handlesNullAndValidation() {
        System.assertEquals(0, ObjectiveSuggestionService.suggest(null).size(), 'null plan -> empty');
        try {
            ObjectiveSuggestionService.accept(null, 'x', null, null);
            System.assert(false, 'should have thrown');
        } catch (Exception e) {
            System.assert(true, 'rejects missing plan/title');
        }
    }
}
