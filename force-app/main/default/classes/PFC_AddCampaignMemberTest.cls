@IsTest
private class PFC_AddCampaignMemberTest {

    @TestSetup
    static void setup() {
        // Org-standard bypass so heavy VRs / autolaunched flows don't block data setup.
        TestDataFactory.bypassAutomation();
    }

    private static Campaign makeCampaign() {
        Campaign c = new Campaign(Name = 'Dedup Test Campaign', Type = 'Other', IsActive = true);
        insert c;
        return c;
    }

    private static Contact makeContact(String lastName) {
        Account a = TestDataFactory.account();
        Contact c = new Contact(FirstName = 'Test', LastName = lastName, AccountId = a.Id);
        insert c;
        return c;
    }

    private static Lead makeLead(String lastName) {
        Lead l = new Lead(FirstName = 'Test', LastName = lastName, Company = 'Acme Ltd');
        insert l;
        return l;
    }

    private static PFC_AddCampaignMember.Request req(Id campaignId, Id contactId, Id leadId) {
        PFC_AddCampaignMember.Request r = new PFC_AddCampaignMember.Request();
        r.campaignId = campaignId;
        r.contactId = contactId;
        r.leadId = leadId;
        r.status = 'Registered';
        return r;
    }

    // The production failure mode: many identical rows bulkified into one call.
    @IsTest
    static void sameKeyBulk_insertsExactlyOne() {
        Campaign camp = makeCampaign();
        Contact con = makeContact('Dedup');

        List<PFC_AddCampaignMember.Request> reqs = new List<PFC_AddCampaignMember.Request>();
        for (Integer i = 0; i < 200; i++) {
            reqs.add(req(camp.Id, con.Id, null));
        }

        Test.startTest();
        PFC_AddCampaignMember.addMembers(reqs);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id AND ContactId = :con.Id],
            'Exactly one CampaignMember for 200 identical requests, with no DUPLICATE_VALUE thrown'
        );
    }

    // Sibling interviews arriving in a second invocation in the same transaction.
    @IsTest
    static void staticDedup_acrossInvocations() {
        Campaign camp = makeCampaign();
        Contact con = makeContact('Static');

        Test.startTest();
        PFC_AddCampaignMember.addMembers(new List<PFC_AddCampaignMember.Request>{ req(camp.Id, con.Id, null) });
        PFC_AddCampaignMember.addMembers(new List<PFC_AddCampaignMember.Request>{ req(camp.Id, con.Id, null) });
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id AND ContactId = :con.Id],
            'Second invocation must not add a duplicate'
        );
    }

    // A member already committed before the call.
    @IsTest
    static void alreadyCommitted_noDuplicateNoError() {
        Campaign camp = makeCampaign();
        Contact con = makeContact('Committed');
        insert new CampaignMember(CampaignId = camp.Id, ContactId = con.Id, Status = 'Registered');

        Test.startTest();
        PFC_AddCampaignMember.addMembers(new List<PFC_AddCampaignMember.Request>{ req(camp.Id, con.Id, null) });
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id AND ContactId = :con.Id],
            'Existing committed member must be left untouched'
        );
    }

    @IsTest
    static void leadDedup_insertsExactlyOne() {
        Campaign camp = makeCampaign();
        Lead ld = makeLead('LeadDedup');

        List<PFC_AddCampaignMember.Request> reqs = new List<PFC_AddCampaignMember.Request>();
        for (Integer i = 0; i < 50; i++) {
            reqs.add(req(camp.Id, null, ld.Id));
        }

        Test.startTest();
        PFC_AddCampaignMember.addMembers(reqs);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id AND LeadId = :ld.Id],
            'Exactly one Lead CampaignMember for 50 identical requests'
        );
    }

    // Distinct members must all be added (dedup must not over-collapse).
    @IsTest
    static void distinctMembers_allInserted() {
        Campaign camp = makeCampaign();
        Account a = TestDataFactory.account();
        List<Contact> cons = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            cons.add(new Contact(FirstName = 'Test', LastName = 'Distinct' + i, AccountId = a.Id));
        }
        insert cons;

        List<PFC_AddCampaignMember.Request> reqs = new List<PFC_AddCampaignMember.Request>();
        for (Contact c : cons) {
            reqs.add(req(camp.Id, c.Id, null));
        }

        Test.startTest();
        PFC_AddCampaignMember.addMembers(reqs);
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id],
            'All five distinct contacts must be added'
        );
    }

    // Missing campaign or member must be skipped, and empty/null input tolerated.
    @IsTest
    static void blankInputs_skippedNoError() {
        Campaign camp = makeCampaign();

        Test.startTest();
        PFC_AddCampaignMember.addMembers(new List<PFC_AddCampaignMember.Request>{
            req(null, null, null),   // nothing
            req(camp.Id, null, null) // campaign but no member
        });
        PFC_AddCampaignMember.addMembers(null);
        PFC_AddCampaignMember.addMembers(new List<PFC_AddCampaignMember.Request>());
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :camp.Id],
            'No members created from blank input'
        );
    }
}
