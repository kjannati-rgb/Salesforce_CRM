@IsTest
private class SalesMotionService_Test {

    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();

    @IsTest
    static void classify_pureRules() {
        Date soon = Date.today().addDays(30);
        Date later = Date.today().addDays(300);
        // active term for this brand, ending soon -> Renewal; ending later -> Upsell
        System.assertEquals('Renewal', SalesMotionService.classify('GCR', true, true, soon, true));
        System.assertEquals('Upsell', SalesMotionService.classify('GCR', true, true, later, true));
        // not this title, but a sibling in the family -> Cross-sell
        System.assertEquals('Cross-sell', SalesMotionService.classify('GAR', false, true, null, false));
        // not this title, no sibling, but prior won business -> Cross-sell
        System.assertEquals('Cross-sell', SalesMotionService.classify('Lexology', false, false, null, true));
        // nothing -> New Business
        System.assertEquals('New Business', SalesMotionService.classify('Lexology', false, false, null, false));
        // brand customer flag ignored when there's no brand
        System.assertEquals('New Business', SalesMotionService.classify(null, true, false, soon, false));
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
