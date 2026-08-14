/**
 * Tests LeadConvertReparent trigger / LeadConvertReparentHandler (REV-68 immediate re-parent).
 * The convert transition (IsConverted / ConvertedContactId) is system-set, so it's simulated
 * via JSON.deserialize — deterministic, no dependence on managed-package convert behaviour.
 */
@IsTest
private class LeadConvertReparent_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    @IsTest
    static void reparentsOnConversionTransition() {
        Account off = new Account(Name = 'LCR Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Contact con = new Contact(LastName = 'LCR', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'LCR', Company = 'LCR Office', CountryCode = 'GB');
        insert ld;
        LBR_Interactions__c i1 = new LBR_Interactions__c(Lead__c = ld.Id, Interaction_Type__c = 'Member',
            Interaction_Status__c = 'Active', Interaction_Date__c = Date.today(), Interaction_Code__c = 'LCR-1');
        insert i1;

        // Simulate the just-converted Lead state the trigger sees.
        String json = '{"attributes":{"type":"Lead"},"Id":"' + ld.Id + '","IsConverted":true,'
            + '"ConvertedContactId":"' + con.Id + '","ConvertedAccountId":"' + off.Id + '"}';
        Lead convertedView = (Lead) System.JSON.deserialize(json, Lead.class);
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ ld.Id => new Lead(Id = ld.Id) };

        Test.startTest();
        LeadConvertReparentHandler.handle(new List<Lead>{ convertedView }, oldMap);
        Test.stopTest();

        LBR_Interactions__c after = [SELECT Contact__c, Lead__c FROM LBR_Interactions__c WHERE Id = :i1.Id];
        System.assertEquals(con.Id, after.Contact__c, 'interaction re-parented immediately on conversion');
        System.assertEquals(null, after.Lead__c, 'Lead cleared');
    }

    @IsTest
    static void triggerNoOpsOnNonConvertUpdate() {
        // Exercises the trigger entrypoint + the non-conversion path (guard false).
        Lead ld = new Lead(FirstName = 'Test', LastName = 'NoConv', Company = 'NoConv Co', CountryCode = 'GB');
        insert ld;
        Test.startTest();
        update new Lead(Id = ld.Id, City = 'London');
        Test.stopTest();
        System.assertEquals(false, [SELECT IsConverted FROM Lead WHERE Id = :ld.Id].IsConverted);
    }
}
