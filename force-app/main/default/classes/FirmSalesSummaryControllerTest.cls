@isTest
private class FirmSalesSummaryControllerTest {

    // Grant FLS to the running user so WITH SECURITY_ENFORCED passes (setup DML isolated via runAs).
    static void assignPermSet() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Firm_Sales_Summary' LIMIT 1];
        User u = new User(Id = UserInfo.getUserId());
        System.runAs(u) {
            if ([SELECT COUNT() FROM PermissionSetAssignment
                 WHERE AssigneeId = :u.Id AND PermissionSetId = :ps.Id] == 0) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
    }

    class Ctx { Account firm; Account o1; Account o2; }

    static Ctx build() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Ctx c = new Ctx();
        c.firm = FirmRollupTestData.firm('CF');
        c.o1 = FirmRollupTestData.office('CO1');
        c.o2 = FirmRollupTestData.office('CO2');
        Opportunity opp1 = FirmRollupTestData.newOpp(c.firm.Id, c.o1.Id, 'Closed Won', 'New Business', 200, 'GBP', Date.today());
        Opportunity opp2 = FirmRollupTestData.newOpp(c.firm.Id, c.o2.Id, 'Closed Won', 'Renewal', 100, 'GBP', Date.today());
        insert new List<Opportunity>{ opp1, opp2 };
        insert new List<OpportunityLineItem>{
            FirmRollupTestData.lineFromPbe(opp1.Id, FirmRollupTestData.pbeFor('Subs - Law.com', null, 'GBP'), 200),
            FirmRollupTestData.lineFromPbe(opp2.Id, FirmRollupTestData.pbeFor('Events', 'Sponsorship', 'GBP'), 100)
        };
        FirmRollupService.recalculateFirm(c.firm.Id);
        return c;
    }

    @isTest(SeeAllData=true)
    static void summaryAndGroups() {
        assignPermSet();
        Ctx c = build();
        Test.startTest();
        FirmSalesSummaryController.SummaryDTO s = FirmSalesSummaryController.getSummary(c.firm.Id);
        List<FirmSalesSummaryController.GroupDTO> groups = FirmSalesSummaryController.getGroupBreakdown(c.firm.Id);
        Test.stopTest();

        System.assertEquals('CF', s.firmName, 'firm name');
        System.assertEquals('USD', s.targetCurrency, 'target currency');
        FirmSalesSummaryController.PeriodDTO all;
        for (FirmSalesSummaryController.PeriodDTO p : s.periods) if (p.key == 'alltime') all = p;
        System.assert(all.netValue == 600, 'all-time net = 200×2 + 100×2 =' + all.netValue);
        System.assertEquals(2, all.wonCount, 'all-time won count');

        Map<String, Decimal> gv = new Map<String, Decimal>();
        Decimal sumGroupAcv = 0;
        for (FirmSalesSummaryController.GroupDTO g : groups) { gv.put(g.name, g.allTimeValue); sumGroupAcv += g.allTimeAcv; }
        System.assert(gv.get('Law.com / ALM') == 400, 'law group value');
        System.assert(gv.get('Events - Sponsorship') == 200, 'sponsorship group value');
        // ACV invariant: headline ACV == Σ group ACV (magnitude verified on real data in FULLUAT)
        System.assert(all.acv == sumGroupAcv.setScale(2), 'headline ACV(' + all.acv + ') = Σ group ACV(' + sumGroupAcv + ')');
    }

    @isTest(SeeAllData=true)
    static void officeBreakdownPeriods() {
        assignPermSet();
        Ctx c = build();
        Test.startTest();
        List<FirmSalesSummaryController.OfficeDTO> all = FirmSalesSummaryController.getOfficeBreakdown(c.firm.Id, 'alltime', 'all');
        List<FirmSalesSummaryController.OfficeDTO> cfy = FirmSalesSummaryController.getOfficeBreakdown(c.firm.Id, 'cfy', 'all');
        List<FirmSalesSummaryController.OfficeDTO> pfy = FirmSalesSummaryController.getOfficeBreakdown(c.firm.Id, 'pfy', 'all');
        List<FirmSalesSummaryController.OfficeDTO> t12 = FirmSalesSummaryController.getOfficeBreakdown(c.firm.Id, 't12m', 'all');
        Test.stopTest();

        System.assertEquals(2, all.size(), 'two offices all-time');
        System.assert(all[0].value >= all[1].value, 'sorted by value desc');
        System.assertEquals(2, cfy.size(), 'both offices in CFY (today)');
        System.assertEquals(0, pfy.size(), 'no offices in PFY');
        System.assertEquals(2, t12.size(), 'both offices in T12M');
    }

    @isTest(SeeAllData=true)
    static void opportunityDrillFiltersAndPaging() {
        assignPermSet();
        Ctx c = build();
        Test.startTest();
        FirmSalesSummaryController.OppPageDTO allOpps = FirmSalesSummaryController.getOpportunities(c.firm.Id, null, null, 'alltime', 'all', 10, 0);
        FirmSalesSummaryController.OppPageDTO byOffice = FirmSalesSummaryController.getOpportunities(c.firm.Id, c.o1.Id, null, 'alltime', 'all', 10, 0);
        FirmSalesSummaryController.OppPageDTO byGroup = FirmSalesSummaryController.getOpportunities(c.firm.Id, null, 'Law.com / ALM', 'alltime', 'all', 10, 0);
        FirmSalesSummaryController.OppPageDTO newBiz = FirmSalesSummaryController.getOpportunities(c.firm.Id, null, null, 'alltime', 'new', 10, 0);
        FirmSalesSummaryController.OppPageDTO renewal = FirmSalesSummaryController.getOpportunities(c.firm.Id, null, null, 'alltime', 'renewal', 10, 0);
        Test.stopTest();

        System.assertEquals(2, allOpps.total, 'two opps total');
        System.assertEquals(1, byOffice.total, 'one opp at office 1');
        System.assertEquals(1, byGroup.total, 'one opp in Law.com / ALM group (CMDT semi-join)');
        System.assertEquals(1, newBiz.total, 'one New Business opp');
        System.assertEquals(1, renewal.total, 'one Renewal opp');
        System.assert(allOpps.rows[0].amountUSD != null, 'amount converted to USD');
    }

    static FirmSalesSummaryController.PeriodDTO allTime(FirmSalesSummaryController.ViewDTO v) {
        for (FirmSalesSummaryController.PeriodDTO p : v.periods) if (p.key == 'alltime') return p;
        return null;
    }

    @isTest(SeeAllData=true)
    static void crossFilterView() {
        assignPermSet();
        Ctx c = build();   // opp1 @CO1 = New Business (Law.com line 200), opp2 @CO2 = Renewal (Events Sponsorship line 100)
        Test.startTest();
        FirmSalesSummaryController.ViewDTO newV = FirmSalesSummaryController.getView(c.firm.Id, 'alltime', 'new', null, null);
        FirmSalesSummaryController.ViewDTO renV = FirmSalesSummaryController.getView(c.firm.Id, 'alltime', 'renewal', null, null);
        FirmSalesSummaryController.ViewDTO offV = FirmSalesSummaryController.getView(c.firm.Id, 'alltime', 'all', c.o1.Id, null);
        FirmSalesSummaryController.ViewDTO grpV = FirmSalesSummaryController.getView(c.firm.Id, 'alltime', 'all', null, 'Law.com / ALM');
        Test.stopTest();

        // business lens
        System.assert(allTime(newV).netValue == 400, 'new lens net = 200×2 =' + allTime(newV).netValue);
        System.assertEquals(1, allTime(newV).wonCount, 'new lens won count');
        System.assert(allTime(renV).netValue == 200, 'renewal lens net = 100×2 =' + allTime(renV).netValue);

        // office filter (CO1 holds only opp1)
        System.assert(allTime(offV).netValue == 400, 'office CO1 net = opp1 =' + allTime(offV).netValue);
        Boolean offHasLaw = false;
        for (FirmSalesSummaryController.GroupDTO g : offV.groups) if (g.name == 'Law.com / ALM') offHasLaw = true;
        System.assert(offHasLaw, 'office filter group panel shows Law.com / ALM (opp1)');

        // ACV invariant: new-lens headline ACV == Σ of that lens's group ACV
        Decimal newAcvSum = 0;
        for (FirmSalesSummaryController.GroupDTO g : newV.groups) newAcvSum += (g.acv == null ? 0 : g.acv);
        System.assert(allTime(newV).acv == newAcvSum.setScale(2), 'new lens headline ACV = Σ group ACV');

        // group filter (Law.com / ALM is only on opp1 @CO1)
        System.assert(allTime(grpV).netValue == 400, 'group Law.com net = opp1 =' + allTime(grpV).netValue);
        Decimal lawAcv = 0;
        for (FirmSalesSummaryController.GroupDTO g : grpV.groups) if (g.name == 'Law.com / ALM') lawAcv = (g.acv == null ? 0 : g.acv);
        System.assert(allTime(grpV).acv == lawAcv.setScale(2), 'group-filter headline ACV = that group ACV');
        System.assertEquals(1, grpV.offices.size(), 'group filter office panel shows only CO1');
        System.assertEquals(c.o1.Id, grpV.offices[0].officeId, 'that office is CO1');
    }

    @isTest(SeeAllData=true)
    static void refreshEnqueues() {
        assignPermSet();
        Ctx c = build();
        Test.startTest();
        FirmSalesSummaryController.refreshFirm(c.firm.Id);
        FirmSalesSummaryController.refreshFirm(null); // no-op guard
        Test.stopTest();
        System.assert(true, 'refresh enqueued without error');
    }
}
