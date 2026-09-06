/** Tests LBRInteractionOrphanMonitor (REV-68 stuck-interaction watchdog). */
@IsTest
private class LBRInteractionOrphanMonitor_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    @IsTest
    static void notifiesWhenStuckRecordsExist() {
        Account off = new Account(Name = 'Mon Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'MonLead', Company = 'Mon Co', CountryCode = 'GB');
        insert ld;
        LBR_Interactions__c i1 = new LBR_Interactions__c(Lead__c = ld.Id, Interaction_Type__c = 'Member',
            Interaction_Status__c = 'Active', Interaction_Date__c = Date.today(), Interaction_Code__c = 'MON-1');
        insert i1;
        List<LBR_Interactions__c> stuck =
            [SELECT Id, Name, Lead__c, Lead__r.Name FROM LBR_Interactions__c WHERE Id = :i1.Id];

        Test.startTest();
        LBRInteractionOrphanMonitor.notify(stuck);
        Test.stopTest();

        System.assertEquals(1, LBRInteractionOrphanMonitor.lastCount, 'counted the stuck record + built/sent alert');
    }

    @IsTest
    static void noOpAndSchedulable() {
        Test.startTest();
        LBRInteractionOrphanMonitor.notify(new List<LBR_Interactions__c>());
        new LBRInteractionOrphanMonitor().execute(null); // run() -> getStuck() (empty) -> notify()
        String jobId = System.schedule('REV68 Orphan Monitor Test', '0 0 3 1 1 ? 2099', new LBRInteractionOrphanMonitor());
        Test.stopTest();

        System.assertEquals(0, LBRInteractionOrphanMonitor.lastCount, 'no alert when nothing is stuck');
        System.assertNotEquals(null, jobId, 'monitor is schedulable');
    }
}
