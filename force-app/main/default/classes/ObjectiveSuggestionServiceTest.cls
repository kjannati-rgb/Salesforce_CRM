@isTest
private class ObjectiveSuggestionServiceTest {

    @isTest
    static void suggestsFromSignalsThenDedupes() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Sug Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c famA = new Plan_Product_Family__c(
            Name = 'Fam A', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert famA;

        insert new Plan_Signal__c(Account_Plan__c = plan.Id, Signal_Type__c = 'Expansion',
            Severity__c = 'High', Source__c = 'Whitespace_Cell', Summary__c = 'White-space threshold crossed',
            Status__c = 'Open', Detected_Date__c = Date.today());

        Test.startTest();
        List<ObjectiveSuggestionService.Suggestion> sug = ObjectiveSuggestionService.suggest(plan.Id);
        Test.stopTest();

        Boolean hasSignal = false;
        for (ObjectiveSuggestionService.Suggestion s : sug) {
            if (s.source == 'Signal') hasSignal = true;
        }
        System.assert(hasSignal, 'open expansion signal suggested');

        Id objId = ObjectiveSuggestionService.accept(plan.Id, 'Pursue: White-space threshold crossed', 100000, famA.Id);
        Plan_Objective__c o = [
            SELECT Linked_Family__c, Target_Amount__c, Status__c FROM Plan_Objective__c WHERE Id = :objId];
        System.assertEquals(famA.Id, o.Linked_Family__c, 'objective linked to the family');
        System.assertEquals(100000, o.Target_Amount__c, 'target carried over');

        for (ObjectiveSuggestionService.Suggestion s : ObjectiveSuggestionService.suggest(plan.Id)) {
            System.assertNotEquals('Pursue: White-space threshold crossed', s.title,
                'the accepted signal suggestion is deduped once an objective covers it');
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
