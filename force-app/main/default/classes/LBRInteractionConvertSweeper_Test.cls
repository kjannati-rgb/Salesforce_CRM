/**
 * Tests LBRInteractionConvertSweeper (REV-68) — the daily safety net that re-parents
 * interactions left on a Lead converted via any path that bypassed LeadConvertInvocable.
 *
 * The batch scope is built with JSON.deserialize so the read-only converted-lead fields
 * (Lead__r.ConvertedContactId/AccountId) can be populated without a real convert — managed
 * packages (DupeBlocker/AddressTools) make callouts during convert that are not allowed in
 * test context, so a real convert can't be relied on for coverage.
 */
@IsTest
private class LBRInteractionConvertSweeper_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    @IsTest
    static void executeReparentsOrphanedInteractions() {
        Account off = new Account(Name = 'Sweep Office', RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert off;
        Contact con = new Contact(LastName = 'Existing', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Orphan', Company = 'Sweep Office', CountryCode = 'GB');
        insert ld;
        // Real interaction left parented to the (notionally converted) Lead.
        LBR_Interactions__c i1 = new LBR_Interactions__c(Lead__c = ld.Id,
            Interaction_Type__c = 'Member', Interaction_Status__c = 'Active',
            Interaction_Date__c = Date.today(), Interaction_Code__c = 'SWEEP-1');
        insert i1;

        // Build a batch-scope row carrying the converted-lead fields the batch reads.
        String json = '{"attributes":{"type":"LBR_Interactions__c"},'
            + '"Id":"' + i1.Id + '",'
            + '"Lead__c":"' + ld.Id + '",'
            + '"Lead__r":{"attributes":{"type":"Lead"},'
            + '"ConvertedContactId":"' + con.Id + '",'
            + '"ConvertedAccountId":"' + off.Id + '"}}';
        LBR_Interactions__c scopeRow = (LBR_Interactions__c) System.JSON.deserialize(json, LBR_Interactions__c.class);

        Test.startTest();
        new LBRInteractionConvertSweeper().execute((Database.BatchableContext) null,
            new List<LBR_Interactions__c>{ scopeRow });
        Test.stopTest();

        LBR_Interactions__c after = [SELECT Contact__c, Lead__c FROM LBR_Interactions__c WHERE Id = :i1.Id];
        System.assertEquals(con.Id, after.Contact__c, 'sweeper re-parented orphaned interaction onto converted Contact');
        System.assertEquals(null, after.Lead__c, 'Lead cleared');
    }

    @IsTest
    static void batchPlumbingAndSchedule() {
        LBRInteractionConvertSweeper sweeper = new LBRInteractionConvertSweeper();
        Test.startTest();
        System.assertNotEquals(null, sweeper.start(null), 'query locator built');
        sweeper.finish(null);
        // execute(SchedulableContext) -> Database.executeBatch; flushes at stopTest with empty scope.
        sweeper.execute((SchedulableContext) null);
        String jobId = System.schedule('REV68 Sweeper Test', '0 0 2 1 1 ? 2099', new LBRInteractionConvertSweeper());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'sweeper is schedulable');
    }
}
