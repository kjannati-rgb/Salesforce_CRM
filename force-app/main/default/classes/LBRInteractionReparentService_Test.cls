/**
 * Tests for LBRInteractionReparentService (REV-68).
 * Exercises reparent() directly with hand-built conversion outcomes so coverage does not
 * depend on managed-package (DupeBlocker/AddressTools) behaviour during a real convert.
 */
@IsTest
private class LBRInteractionReparentService_Test {

    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
    private static final Id NB_RT =
        Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('New_Business').getRecordTypeId();

    @TestSetup
    static void killSwitch() {
        // Mute the org's heavy autolaunch flows + VRs so the test focuses on REV-68 logic.
        insert new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true, Disable_Validation_Rules__c = true);
    }

    // ---- helpers -------------------------------------------------------------

    private static Account office(String name, Id ultimate) {
        return new Account(Name = name, RecordTypeId = OFFICE_RT,
            BillingCountryCode = 'GB', BillingCity = 'London', Ultimate_Account__c = ultimate);
    }

    private static LBR_Interactions__c onLead(Id leadId, String code, String type, Date d) {
        return new LBR_Interactions__c(
            Lead__c = leadId, Interaction_Type__c = type, Interaction_Status__c = 'Active',
            Interaction_Date__c = d, Interaction_Code__c = code);
    }

    private static LBR_Interactions__c onContact(Id contactId, Id acctId, String code, String type, Date d) {
        return new LBR_Interactions__c(
            Contact__c = contactId, Account__c = acctId, Interaction_Type__c = type,
            Interaction_Status__c = 'Active', Interaction_Date__c = d, Interaction_Code__c = code);
    }

    private static LBRInteractionReparentService.ConvertedLead cl(Id leadId, Id contactId, Id acctId, Id oppId) {
        return new LBRInteractionReparentService.ConvertedLead(leadId, contactId, acctId, oppId);
    }

    // ---- tests ---------------------------------------------------------------

    @IsTest
    static void reparentsSingleAndMaintainsCount() {
        Account firm = new Account(Name = 'Firm A', RecordTypeId = FIRM_RT,
            BillingCountryCode = 'GB', BillingCity = 'London');
        insert firm;
        Account off = office('Office A', firm.Id);
        insert off;
        Contact con = new Contact(LastName = 'Converted', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Src', Company = 'OfficeA', CountryCode = 'GB');
        insert ld;
        LBR_Interactions__c i1 = onLead(ld.Id, 'CODE-1', 'Member', Date.today());
        insert i1;

        Test.startTest();
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
            cl(ld.Id, con.Id, off.Id, null) });
        Test.stopTest();

        LBR_Interactions__c after = [
            SELECT Contact__c, Account__c, Ultimate_Account__c, Lead__c
            FROM LBR_Interactions__c WHERE Id = :i1.Id];
        System.assertEquals(con.Id, after.Contact__c, 'Contact re-parented');
        System.assertEquals(off.Id, after.Account__c, 'Account stamped');
        System.assertEquals(null, after.Lead__c, 'Lead cleared in same DML');
        Account offAfter = [SELECT Ultimate_Account__c FROM Account WHERE Id = :off.Id];
        System.assertEquals(offAfter.Ultimate_Account__c, after.Ultimate_Account__c, 'Ultimate from parent Account');

        Contact c = [SELECT Count_of_LBR_Interactions__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals(1, c.Count_of_LBR_Interactions__c, 'count trigger maintained replacement field');
    }

    @IsTest
    static void dedupesByCompositeWhenNoCode() {
        Account off = office('Office C', null);
        insert off;
        Contact con = new Contact(LastName = 'C', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Src', Company = 'OfficeC', CountryCode = 'GB');
        insert ld;

        Date d = Date.today();
        insert onContact(con.Id, off.Id, null, 'Member', d);
        LBR_Interactions__c leadDup = new LBR_Interactions__c(
            Lead__c = ld.Id, Interaction_Type__c = 'Member', Interaction_Status__c = 'Active', Interaction_Date__c = d);
        insert leadDup;

        Test.startTest();
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
            cl(ld.Id, con.Id, off.Id, null) });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM LBR_Interactions__c WHERE Id = :leadDup.Id],
            'composite-match duplicate deleted when no Interaction_Code__c');
    }

    @IsTest
    static void insertsContact2InteractionAndSkipsExistingPair() {
        Account off = office('Office D', null);
        insert off;
        Contact con = new Contact(LastName = 'C', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Src', Company = 'OfficeD', CountryCode = 'GB');
        insert ld;
        Opportunity opp = new Opportunity(Name = 'Opp D', StageName = 'Identify', Probability = 10,
            CloseDate = Date.today().addMonths(2), AccountId = off.Id, RecordTypeId = NB_RT);
        insert opp;

        LBR_Interactions__c i1 = onLead(ld.Id, 'C-OPP', 'Member', Date.today());
        insert i1;
        // Pre-existing C2I pair (interaction, opp) to exercise the skip branch.
        insert new Contact2Interaction__c(Contact__c = con.Id, LBR_Interactions__c = i1.Id, Opportunity__c = opp.Id);

        Test.startTest();
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
            cl(ld.Id, con.Id, off.Id, opp.Id) });
        Test.stopTest();

        List<Contact2Interaction__c> pairs = [
            SELECT Contact__c, Opportunity__c FROM Contact2Interaction__c WHERE LBR_Interactions__c = :i1.Id];
        System.assertEquals(1, pairs.size(), 'existing (interaction, opp) pair not duplicated');
        System.assertEquals(opp.Id, pairs[0].Opportunity__c);
    }

    @IsTest
    static void insertsContact2InteractionWhenMissing() {
        Account off = office('Office E', null);
        insert off;
        Contact con = new Contact(LastName = 'C', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Src', Company = 'OfficeE', CountryCode = 'GB');
        insert ld;
        Opportunity opp = new Opportunity(Name = 'Opp E', StageName = 'Identify', Probability = 10,
            CloseDate = Date.today().addMonths(2), AccountId = off.Id, RecordTypeId = NB_RT);
        insert opp;
        LBR_Interactions__c i1 = onLead(ld.Id, 'E-OPP', 'Member', Date.today());
        insert i1;

        Test.startTest();
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
            cl(ld.Id, con.Id, off.Id, opp.Id) });
        Test.stopTest();

        List<Contact2Interaction__c> pairs = [
            SELECT Contact__c, Opportunity__c FROM Contact2Interaction__c WHERE LBR_Interactions__c = :i1.Id];
        System.assertEquals(1, pairs.size(), 'C2I inserted for surviving interaction with an Opportunity');
        System.assertEquals(con.Id, pairs[0].Contact__c);
    }

    @IsTest
    static void handlesNullAndEmptyInput() {
        Test.startTest();
        LBRInteractionReparentService.reparent(null);
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>());
        // a convert with no matching interactions is a no-op
        Account off = office('Office F', null);
        insert off;
        Contact con = new Contact(LastName = 'C', AccountId = off.Id);
        insert con;
        Lead ld = new Lead(FirstName = 'Test', LastName = 'Src', Company = 'OfficeF', CountryCode = 'GB');
        insert ld;
        LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
            cl(ld.Id, con.Id, off.Id, null) });
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM LBR_Interactions__c WHERE Contact__c = :con.Id]);
    }

    @IsTest
    static void reparentsBulk() {
        Account off = office('Bulk Office', null);
        insert off;

        Integer n = 200;
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < n; i++) leads.add(new Lead(FirstName = 'T' + i, LastName = 'L' + i, Company = 'Co' + i, CountryCode = 'GB'));
        insert leads;
        List<Contact> cons = new List<Contact>();
        for (Integer i = 0; i < n; i++) cons.add(new Contact(LastName = 'C' + i, AccountId = off.Id));
        insert cons;
        List<LBR_Interactions__c> ints = new List<LBR_Interactions__c>();
        for (Integer i = 0; i < n; i++) ints.add(onLead(leads[i].Id, 'BULK-' + i, 'Member', Date.today()));
        insert ints;

        List<LBRInteractionReparentService.ConvertedLead> converts =
            new List<LBRInteractionReparentService.ConvertedLead>();
        for (Integer i = 0; i < n; i++) converts.add(cl(leads[i].Id, cons[i].Id, off.Id, null));

        Test.startTest();
        LBRInteractionReparentService.reparent(converts);
        Test.stopTest();

        System.assertEquals(n, [SELECT COUNT() FROM LBR_Interactions__c WHERE Lead__c = null AND Contact__c != null],
            'all 200 lead-side interactions re-parented in a single bulk call');
    }
}
