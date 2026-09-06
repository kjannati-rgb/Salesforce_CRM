/**
 * Tests the LBRInteractionCount trigger / LBRInteractionCountHandler (REV-68) — the
 * replacement for the roll-up summary removed when Contact__c became a Lookup.
 */
@IsTest
private class LBRInteractionCount_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    private static Decimal countOn(Id contactId) {
        return [SELECT Count_of_LBR_Interactions__c FROM Contact WHERE Id = :contactId].Count_of_LBR_Interactions__c;
    }

    @IsTest
    static void maintainsCountOnInsertDeleteUndelete() {
        Account off = new Account(Name = 'Cnt Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Contact con = new Contact(LastName = 'Counter', AccountId = off.Id);
        insert con;

        LBR_Interactions__c a = new LBR_Interactions__c(Contact__c = con.Id, Account__c = off.Id,
            Interaction_Type__c = 'Member', Interaction_Status__c = 'Active',
            Interaction_Date__c = Date.today(), Interaction_Code__c = 'K1');
        LBR_Interactions__c b = new LBR_Interactions__c(Contact__c = con.Id, Account__c = off.Id,
            Interaction_Type__c = 'Member', Interaction_Status__c = 'Active',
            Interaction_Date__c = Date.today().addDays(1), Interaction_Code__c = 'K2');

        Test.startTest();
        insert new List<LBR_Interactions__c>{ a, b };
        System.assertEquals(2, countOn(con.Id), 'count after insert');

        delete b;
        System.assertEquals(1, countOn(con.Id), 'count after delete');

        undelete b;
        System.assertEquals(2, countOn(con.Id), 'count after undelete');
        Test.stopTest();
    }
}
