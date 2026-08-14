@IsTest
private class LeadMatchSelectService_Test {

    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void seed() {
        // Firms
        Account acme  = firm('Acme Law Demo',   'acme-demo.com');
        Account beta  = firm('Beta Legal Demo', 'beta-demo.com');
        Account cee1  = firm('Cee One Demo',    'shared-demo.com');
        Account cee2  = firm('Cee Two Demo',    'shared-demo.com');
        Account empty = firm('Empty Firm Demo', 'empty-demo.com');
        insert new List<Account>{ acme, beta, cee1, cee2, empty };

        // Offices
        insert new List<Account>{
            // Acme: UK office is also the opp leader -> clean ONECLICK
            office('Acme London', acme.Id, 'GB', 'London',   5, 50000),
            office('Acme New York', acme.Id, 'US', 'New York', 0, 0),
            // Beta: lead matches London exactly, but a nearby UK office (Manchester)
            // carries far more opportunity weight -> dup-review conflict.
            office('Beta London', beta.Id, 'GB', 'London',     1, 10000),
            office('Beta Manchester', beta.Id, 'GB', 'Manchester', 50, 900000),
            // Shared-domain firms each have one office
            office('Cee One London', cee1.Id, 'GB', 'London', 1, 1000),
            office('Cee Two Paris',  cee2.Id, 'FR', 'Paris',  1, 1000)
            // Empty Firm intentionally has no Office
        };
    }

    // ---- helpers ----
    private static Account firm(String name, String domain) {
        return new Account(Name = name, RecordTypeId = FIRM_RT, Match_Domain__c = domain);
    }
    private static Account office(String name, Id firmId, String cc, String city, Double wonCnt, Double wonVal) {
        return new Account(Name = name, RecordTypeId = OFFICE_RT, Ultimate_Account__c = firmId,
            BillingCountryCode = cc, BillingCity = city,
            No_of_Won_Office_Opportunities__c = wonCnt,
            Val_of_Won_Office_Opportunities__c = wonVal,
            CFY_No_of_Won_Office_Opportunities__c = wonCnt);
    }
    private static LeadMatchSelectService.Request req(String email, String cc, String region, String website) {
        LeadMatchSelectService.Request r = new LeadMatchSelectService.Request();
        r.recordId = null; r.email = email; r.countryCode = cc; r.region = region; r.website = website;
        return r;
    }
    private static LeadMatchSelectService.Result one(LeadMatchSelectService.Request r) {
        return LeadMatchSelectService.matchAndSelect(new List<LeadMatchSelectService.Request>{ r })[0];
    }

    // ---- tests ----

    @IsTest
    static void oneClick_uniqueFirm_locationAndOppAgree() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('jane@acme-demo.com', 'GB', 'London', null));
        Test.stopTest();
        System.assertEquals('ONECLICK', res.confidenceTier, res.matchEvidence);
        System.assertEquals('Acme Law Demo', res.resolvedFirmName);
        System.assertEquals('Acme London', res.recommendedOfficeName);
        System.assertEquals(false, res.conflict);
        System.assertEquals(true, res.existingCustomer, 'Office has won opps');
        System.assertEquals(2, res.candidateOffices.size());
    }

    @IsTest
    static void conflict_locationVsOpportunities() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('bob@beta-demo.com', 'GB', 'London', null));
        Test.stopTest();
        System.assertEquals('REVIEW', res.confidenceTier);
        System.assertEquals(true, res.conflict, 'exact-location office vs higher-opp nearby office');
        System.assertEquals('Beta London', res.recommendedOfficeName, 'recommend by location');
    }

    @IsTest
    static void review_domainResolvesToMultipleFirms() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('x@shared-demo.com', 'GB', null, null));
        Test.stopTest();
        System.assertEquals('REVIEW', res.confidenceTier);
        System.assertEquals(null, res.resolvedFirmId, 'ambiguous; no single firm');
    }

    @IsTest
    static void guidedCreate_noMatch() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('x@nomatch-demo.com', 'GB', null, null));
        Test.stopTest();
        System.assertEquals('GUIDED_CREATE', res.confidenceTier);
    }

    @IsTest
    static void guidedCreate_firmWithNoOffice() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('x@empty-demo.com', 'GB', null, null));
        Test.stopTest();
        System.assertEquals('GUIDED_CREATE', res.confidenceTier);
        System.assertEquals('Empty Firm Demo', res.resolvedFirmName, 'firm resolved, just no office');
    }

    @IsTest
    static void freeMail_fallsBackToWebsiteHost() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req('jane@gmail.com', 'GB', 'London', 'https://www.acme-demo.com/contact'));
        Test.stopTest();
        System.assertEquals('ONECLICK', res.confidenceTier, 'resolved via website host');
        System.assertEquals('Acme Law Demo', res.resolvedFirmName);
    }

    @IsTest
    static void noKey_blankEmailAndWebsite() {
        Test.startTest();
        LeadMatchSelectService.Result res = one(req(null, 'GB', null, null));
        Test.stopTest();
        System.assertEquals('GUIDED_CREATE', res.confidenceTier);
    }

    @IsTest
    static void bulk_200_withinLimits() {
        List<LeadMatchSelectService.Request> reqs = new List<LeadMatchSelectService.Request>();
        for (Integer i = 0; i < 200; i++) {
            reqs.add(req('user' + i + '@acme-demo.com', 'GB', 'London', null));
        }
        Test.startTest();
        List<LeadMatchSelectService.Result> res = LeadMatchSelectService.matchAndSelect(reqs);
        Test.stopTest();
        System.assertEquals(200, res.size());
        System.assertEquals('ONECLICK', res[0].confidenceTier);
        // bulk-safety: SOQL is CONSTANT regardless of batch size (not per-record).
        System.assert(Limits.getQueries() <= 10,
            '200 records should use a constant handful of queries, not scale per-record. Used: '
            + Limits.getQueries());
    }

    @IsTest
    static void freeMail_loadsFromCmdt() {
        Set<String> fm = LeadMatchSelectService.freeMail();
        System.assert(fm.contains('gmail.com'), 'baseline free-mail present');
        System.assert(fm.contains('qq.com'), 'CMDT-extended free-mail present (qq.com)');
    }

    @IsTest
    static void emptyInput_returnsEmpty() {
        Test.startTest();
        System.assertEquals(0, LeadMatchSelectService.matchAndSelect(null).size());
        System.assertEquals(0,
            LeadMatchSelectService.matchAndSelect(new List<LeadMatchSelectService.Request>()).size());
        Test.stopTest();
    }
}
