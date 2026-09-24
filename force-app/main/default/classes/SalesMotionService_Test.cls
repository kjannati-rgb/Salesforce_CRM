@IsTest
private class SalesMotionService_Test {

    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();

    @IsTest
    static void classify_pureRules() {
        Date soon = Date.today().addDays(30);
        Date later = Date.today().addDays(300);
        // active term for this brand, ending soon -> Renewal; ending later -> Upsell
        System.assertEquals('Renewal', SalesMotionService.classify('GCR', true, true, soon));
        System.assertEquals('Upsell', SalesMotionService.classify('GCR', true, true, later));
        // not this title, but a sibling in the family -> Cross-sell
        System.assertEquals('Cross-sell', SalesMotionService.classify('GAR', false, true, null));
        // no active subscription relevant to the enquiry -> New Business
        System.assertEquals('New Business', SalesMotionService.classify('Lexology', false, false, null));
        // no resolvable product: nothing to be relevant to, whatever the flags say
        System.assertEquals('New Business', SalesMotionService.classify(null, true, false, soon));
        System.assertEquals('New Business', SalesMotionService.classify(null, false, true, null));
    }

    @IsTest
    static void wonBusinessOnOtherBrands_isNewBusiness_notCrossSell() {
        // Regression (Khris Fenton, 24 Sep 2026): a Law.com enquiry at a firm with Closed Won
        // deals on OTHER products is New Business for Law.com, not a cross-sell.
        Account firm = new Account(Name = 'Won Elsewhere Firm', RecordTypeId = FIRM_RT);
        insert firm;
        Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
        insert new Account(Name = 'Won Elsewhere Office', RecordTypeId = officeRt, Ultimate_Account__c = firm.Id,
            No_of_Won_Office_Opportunities__c = 7);
        Test.startTest();
        SalesMotionService.Assessment a = SalesMotionService.assess(firm.Id, 'Law.com');
        Test.stopTest();
        System.assertEquals(true, a.knownAccount, 'won business is still surfaced as relationship context');
        System.assertEquals('New Business', a.motion, 'but it never makes the enquiry a cross-sell');
    }

    private static User userInTeam(String team) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String key = 'tm' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(6);
        User u = new User(FirstName = 'Team', LastName = 'Rep', Alias = key.left(8), Email = key + '@lbr-demo.test',
            Username = key + '.' + System.currentTimeMillis() + '@lbr-demo.test', ProfileId = p.Id, Team__c = team,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_GB', TimeZoneSidKey = 'Europe/London');
        insert u;
        return u;
    }

    @IsTest
    static void repFallback_teamLineDecidesOnlyWhenLeadNamesNoProduct() {
        // Commercial (Khris Fenton, 24 Sep 2026): the opportunity owner's product line decides the
        // motion when the lead doesn't say which product it's about.
        User lawcomRep = userInTeam('ALM Legal - Info Services');
        User dataRep = userInTeam('Data');
        Test.startTest();
        SalesMotionService.Assessment noProduct = SalesMotionService.assessForRep(null, null, null, lawcomRep.Id);
        SalesMotionService.Assessment namedProduct = SalesMotionService.assessForRep(null, 'Lexology Intelligence', null, lawcomRep.Id);
        SalesMotionService.Assessment freeText = SalesMotionService.assessForRep(null, null, 'Benefits Pro', lawcomRep.Id);
        SalesMotionService.Assessment unmappedTeam = SalesMotionService.assessForRep(null, null, null, dataRep.Id);
        Test.stopTest();
        System.assertEquals('Law.com', noProduct.brand, 'no product on the lead -> the rep\'s line');
        System.assertEquals(true, noProduct.brandFromRep);
        System.assertEquals('Lexology Intelligence', namedProduct.brand, 'a recognised product on the lead still wins');
        System.assertEquals(false, namedProduct.brandFromRep);
        System.assertEquals('Law.com', freeText.brand, 'unrecognised free text falls back to the rep\'s line too');
        System.assertEquals(null, unmappedTeam.brand, 'a team with no single product line changes nothing');
        System.assertEquals(false, unmappedTeam.brandFromRep);
        System.assertEquals('New Business', unmappedTeam.motion);
    }

    @IsTest
    static void firmHasWonBusiness_falseWhenNone() {
        Account firm = new Account(Name = 'No Won Firm', RecordTypeId = FIRM_RT);
        insert firm;
        Test.startTest();
        System.assertEquals(false, SalesMotionService.firmHasWonBusiness(null));
        System.assertEquals(false, SalesMotionService.firmHasWonBusiness(firm.Id));
        Test.stopTest();
    }

    @IsTest
    static void assess_unknownWhenNoBrandOrFirm() {
        SalesMotionService.Assessment a = SalesMotionService.assess(null, null);
        System.assertEquals('unknown', a.brandStatus);
        System.assertEquals('New Business', a.motion);
        System.assertEquals(false, a.brandCustomer);
    }

    @IsTest
    static void assess_prospectWiresThrough() {
        Account firm = new Account(Name = 'Assess Prospect Firm', RecordTypeId = FIRM_RT);
        insert firm;
        Test.startTest();
        SalesMotionService.Assessment a = SalesMotionService.assess(firm.Id, 'GCR');
        Test.stopTest();
        System.assertEquals('prospect', a.brandStatus, 'no GCR sub seeded');
        System.assertEquals('Specialist Platforms', a.brandFamily, 'GCR family wired through');
        System.assertEquals('New Business', a.motion, 'no title, no sibling, no won opps');
    }

    @IsTest
    static void invocable_returnsAssessment() {
        Account firm = new Account(Name = 'Invocable Firm', RecordTypeId = FIRM_RT);
        insert firm;
        // office under the firm, to exercise the firm walk-up
        Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
        Account office = new Account(Name = 'Invocable Office', RecordTypeId = officeRt, Ultimate_Account__c = firm.Id);
        insert office;
        SalesMotionService.Request r = new SalesMotionService.Request();
        r.firmId = office.Id;          // pass an Office; service walks up to the Firm
        r.formBrand = 'GAR';
        Test.startTest();
        List<SalesMotionService.Response> resp =
            SalesMotionService.assessInvocable(new List<SalesMotionService.Request>{ r });
        Test.stopTest();
        System.assertEquals(1, resp.size());
        System.assertEquals('GAR', resp[0].brand, 'form brand resolved to canonical');
        System.assertEquals('Specialist Platforms', resp[0].brandFamily);
        System.assertNotEquals(null, resp[0].motion);
    }
}
