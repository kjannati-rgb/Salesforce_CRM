/** Tests LBRInteractionCountBackfill (REV-68 one-off count recompute). */
@IsTest
private class LBRInteractionCountBackfill_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    @IsTest
    static void backfillsCountForExistingContacts() {
        Account off = new Account(Name = 'BF Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Contact con = new Contact(LastName = 'BF', AccountId = off.Id);
        insert con;
        insert new List<LBR_Interactions__c>{
            new LBR_Interactions__c(Contact__c = con.Id, Account__c = off.Id, Interaction_Type__c = 'Member',
                Interaction_Status__c = 'Active', Interaction_Date__c = Date.today(), Interaction_Code__c = 'BF1'),
            new LBR_Interactions__c(Contact__c = con.Id, Account__c = off.Id, Interaction_Type__c = 'Member',
                Interaction_Status__c = 'Active', Interaction_Date__c = Date.today().addDays(1), Interaction_Code__c = 'BF2')
        };
        // Simulate a pre-backfill Contact whose count is stale/blank.
        update new Contact(Id = con.Id, Count_of_LBR_Interactions__c = 0);

        Test.startTest();
        Database.executeBatch(new LBRInteractionCountBackfill(), 200);
        Test.stopTest();

        System.assertEquals(2,
            [SELECT Count_of_LBR_Interactions__c FROM Contact WHERE Id = :con.Id].Count_of_LBR_Interactions__c,
            'backfill recomputed the count');
    }
}
