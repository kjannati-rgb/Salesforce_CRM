@isTest
private class FirmRollupServiceTest {

    static Map<String, Firm_Product_Group_Rollup_USD__c> groupsOf(Id firmId) {
        Map<String, Firm_Product_Group_Rollup_USD__c> m = new Map<String, Firm_Product_Group_Rollup_USD__c>();
        for (Firm_Product_Group_Rollup_USD__c g : [
                SELECT Commercial_Group__c, Won_Value_AllTime_USD__c, Won_Items_AllTime__c,
                       Won_Value_CFY_USD__c, Won_Items_CFY__c, Won_Value_T12M_USD__c, Won_Items_T12M__c
                FROM Firm_Product_Group_Rollup_USD__c WHERE Firm__c = :firmId]) {
            m.put(g.Commercial_Group__c, g);
        }
        return m;
    }

    @isTest static void headlineNettingAndPeriods() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Account firm = FirmRollupTestData.firm('F1');
        Account off = FirmRollupTestData.office('O1');
        Date today = Date.today();
        Date priorFy = Date.newInstance(today.year() - 1, 1, 1);
        insert new List<Opportunity>{
            FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 1000, 'GBP', today),
            FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'Renewal', 500, 'USD', today),
            FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won - Cancellation', 'Cancellation', -200, 'GBP', today),
            FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 400, 'EUR', priorFy)
        };

        Test.startTest();
        FirmRollupService.recalculateFirm(firm.Id);
        Test.stopTest();

        Account r = [SELECT Firm_Won_Value_AllTime_USD__c, Firm_Won_Count_AllTime__c,
                            Firm_Cancellation_Value_AllTime_USD__c, Firm_Cancellation_Count_AllTime__c,
                            Firm_Won_Value_CFY_USD__c, Firm_Won_Count_CFY__c,
                            Firm_Won_Value_PFY_USD__c, Firm_Won_Count_PFY__c,
                            Firm_Won_Value_T12M_USD__c, Firm_Won_Count_T12M__c,
                            Firm_Rollup_Last_Refreshed__c
                     FROM Account WHERE Id = :firm.Id];
        // GBP×2, USD×1, EUR÷2 :  net = 2000 + 500 - 400 + 200 = 2300
        System.assert(r.Firm_Won_Value_AllTime_USD__c == 2300, 'all-time net=' + r.Firm_Won_Value_AllTime_USD__c);
        System.assertEquals(3, r.Firm_Won_Count_AllTime__c.intValue(), 'won count (CW only)');
        System.assert(r.Firm_Cancellation_Value_AllTime_USD__c == -400, 'cancel value=' + r.Firm_Cancellation_Value_AllTime_USD__c);
        System.assertEquals(1, r.Firm_Cancellation_Count_AllTime__c.intValue(), 'cancel count');
        System.assert(r.Firm_Won_Value_CFY_USD__c == 2100, 'CFY net=' + r.Firm_Won_Value_CFY_USD__c);
        System.assertEquals(2, r.Firm_Won_Count_CFY__c.intValue(), 'CFY won count');
        System.assert(r.Firm_Won_Value_PFY_USD__c == 200, 'PFY net=' + r.Firm_Won_Value_PFY_USD__c);
        System.assertEquals(1, r.Firm_Won_Count_PFY__c.intValue(), 'PFY won count');
        System.assert(r.Firm_Won_Value_T12M_USD__c == 2100, 'T12M net=' + r.Firm_Won_Value_T12M_USD__c);
        System.assertEquals(2, r.Firm_Won_Count_T12M__c.intValue(), 'T12M won count');
        System.assertNotEquals(null, r.Firm_Rollup_Last_Refreshed__c, 'refresh stamp set');
    }

    @isTest static void groupsEventsSplitFallbackAndSumEqualsNet() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Account firm = FirmRollupTestData.firm('F2');
        Account off = FirmRollupTestData.office('O2');
        Product2 pSpon = FirmRollupTestData.product('Events', 'Sponsorship');
        Product2 pTick = FirmRollupTestData.product('Events', 'Ticket');
        Product2 pEvtNull = FirmRollupTestData.product('Events', null);
        Product2 pWeb = FirmRollupTestData.product('Events', 'Webinar');
        Product2 pLaw = FirmRollupTestData.product('Subs - Law.com', null);
        Product2 pUnknown = FirmRollupTestData.product('Mystery Family', null);

        Opportunity opp = FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 530, 'GBP', Date.today());
        insert opp;
        insert new List<OpportunityLineItem>{
            FirmRollupTestData.line(opp.Id, pSpon.Id, 100, 'GBP'),
            FirmRollupTestData.line(opp.Id, pTick.Id, 100, 'GBP'),
            FirmRollupTestData.line(opp.Id, pEvtNull.Id, 50, 'GBP'),
            FirmRollupTestData.line(opp.Id, pWeb.Id, 50, 'GBP'),
            FirmRollupTestData.line(opp.Id, pLaw.Id, 200, 'GBP'),
            FirmRollupTestData.line(opp.Id, pUnknown.Id, 30, 'GBP')
        };

        Test.startTest();
        FirmRollupService.recalculateFirm(firm.Id);
        Test.stopTest();

        Map<String, Firm_Product_Group_Rollup_USD__c> g = groupsOf(firm.Id);
        System.assertEquals(5, g.size(), 'five distinct groups: ' + g.keySet());
        System.assertEquals(1, g.get('Events - Sponsorship').Won_Items_AllTime__c.intValue(), 'sponsorship items');
        System.assertEquals(1, g.get('Events - Delegate Ticket').Won_Items_AllTime__c.intValue(), 'ticket items');
        System.assertEquals(2, g.get('Events - Other').Won_Items_AllTime__c.intValue(), 'null+Webinar -> Events-Other');
        System.assertEquals(1, g.get('Law.com / ALM').Won_Items_AllTime__c.intValue(), 'law items');
        System.assertEquals(1, g.get('Other / POS / Reports').Won_Items_AllTime__c.intValue(), 'unmapped -> default');
        System.assert(g.get('Events - Sponsorship').Won_Value_AllTime_USD__c == 200, 'spon value');
        System.assert(g.get('Events - Other').Won_Value_AllTime_USD__c == 200, 'events-other value');

        Decimal sumGroups = 0;
        for (Firm_Product_Group_Rollup_USD__c row : g.values()) sumGroups += row.Won_Value_AllTime_USD__c;
        Account r = [SELECT Firm_Won_Value_AllTime_USD__c FROM Account WHERE Id = :firm.Id];
        System.assert(sumGroups == r.Firm_Won_Value_AllTime_USD__c, 'Σgroups=' + sumGroups + ' net=' + r.Firm_Won_Value_AllTime_USD__c);
        System.assert(r.Firm_Won_Value_AllTime_USD__c == 1060, 'net=530×2');
    }

    @isTest static void idempotencyAndDeleteOnZero() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Account firm = FirmRollupTestData.firm('F3');
        Account off = FirmRollupTestData.office('O3');
        Product2 pLaw = FirmRollupTestData.product('Subs - Law.com', null);
        Product2 pSpon = FirmRollupTestData.product('Events', 'Sponsorship');
        Opportunity opp = FirmRollupTestData.newOpp(firm.Id, off.Id, 'Closed Won', 'New Business', 300, 'GBP', Date.today());
        insert opp;
        OpportunityLineItem lawLine = FirmRollupTestData.line(opp.Id, pLaw.Id, 200, 'GBP');
        OpportunityLineItem sponLine = FirmRollupTestData.line(opp.Id, pSpon.Id, 100, 'GBP');
        insert new List<OpportunityLineItem>{ lawLine, sponLine };

        Test.startTest();
        FirmRollupService.recalculateFirm(firm.Id);
        FirmRollupService.recalculateFirm(firm.Id); // idempotent re-run
        System.assertEquals(2, groupsOf(firm.Id).size(), 'no duplicate rows after re-run');

        delete sponLine;                              // group drops to zero
        FirmRollupService.recalculateFirm(firm.Id);
        Test.stopTest();

        Map<String, Firm_Product_Group_Rollup_USD__c> g = groupsOf(firm.Id);
        System.assertEquals(1, g.size(), 'delete-on-zero removed the emptied group');
        System.assert(g.containsKey('Law.com / ALM'), 'remaining group survives');
    }

    @isTest static void subsActiveExpiredTerminated() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Account firm = FirmRollupTestData.firm('F4');
        Account off = FirmRollupTestData.office('O4');
        Date t = Date.today();
        insert new List<SBQQ__Subscription__c>{
            FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(-10), t.addDays(10), 100, 'GBP', null),   // active
            FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(-30), t.addDays(-5), 100, 'GBP', null),    // expired
            FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(5), t.addDays(40), 100, 'GBP', null),      // future
            FirmRollupTestData.sub(firm.Id, off.Id, t.addDays(-10), t.addDays(10), 100, 'GBP', t.addDays(-1)) // terminated, in-window
        };

        Test.startTest();
        FirmRollupService.recalculateFirm(firm.Id);
        Test.stopTest();

        Account r = [SELECT Firm_Active_Subscriptions__c, Firm_Active_Sub_Value_USD__c FROM Account WHERE Id = :firm.Id];
        // locked definition omits terminated filter -> 2 in-window (active + terminated)
        System.assertEquals(2, r.Firm_Active_Subscriptions__c.intValue(), 'active subs (in-window)');
        System.assert(r.Firm_Active_Sub_Value_USD__c == 400, 'active sub value=2×100×2 =' + r.Firm_Active_Sub_Value_USD__c);
    }

    @isTest static void zeroFirmAndNullFirmOpp() {
        FirmRollupTriggerGuard.bypass = true;
        FirmRollupTestData.injectStandardConfig();
        Account firm = FirmRollupTestData.firm('F5');
        Account off = FirmRollupTestData.office('O5');
        // a won opp with NO firm link -> must not roll into firm F5
        insert FirmRollupTestData.newOpp(null, off.Id, 'Closed Won', 'New Business', 999, 'GBP', Date.today());

        Test.startTest();
        FirmRollupService.recalculateFirm(firm.Id);
        Test.stopTest();

        Account r = [SELECT Firm_Won_Value_AllTime_USD__c, Firm_Won_Count_AllTime__c FROM Account WHERE Id = :firm.Id];
        System.assert(r.Firm_Won_Value_AllTime_USD__c == 0, 'zero-opp firm = 0');
        System.assertEquals(0, r.Firm_Won_Count_AllTime__c.intValue(), 'zero count');
        System.assertEquals(0, groupsOf(firm.Id).size(), 'no group rows');
    }

    @isTest static void reparentRecomputesBothFirms() {
        FirmRollupTriggerGuard.bypass = true;
        OpportunityAnalyticsCreate.activeOverride = false; // keep existing update-handler quiet
        FirmRollupTestData.injectStandardConfig();
        Account firmA = FirmRollupTestData.firm('A');
        Account firmB = FirmRollupTestData.firm('B');
        Account off = FirmRollupTestData.office('O6');
        Opportunity opp = FirmRollupTestData.newOpp(firmA.Id, off.Id, 'Closed Won', 'New Business', 1000, 'GBP', Date.today());
        insert opp;

        Test.startTest();
        FirmRollupService.recalculateFirms(new Set<Id>{ firmA.Id, firmB.Id });
        System.assert([SELECT Firm_Won_Value_AllTime_USD__c FROM Account WHERE Id = :firmA.Id].Firm_Won_Value_AllTime_USD__c == 2000, 'A populated');

        opp.Ultimate_Account__c = firmB.Id;
        update opp;
        FirmRollupService.recalculateFirms(new Set<Id>{ firmA.Id, firmB.Id });
        Test.stopTest();

        System.assert([SELECT Firm_Won_Value_AllTime_USD__c FROM Account WHERE Id = :firmA.Id].Firm_Won_Value_AllTime_USD__c == 0, 'A reset after move');
        System.assert([SELECT Firm_Won_Value_AllTime_USD__c FROM Account WHERE Id = :firmB.Id].Firm_Won_Value_AllTime_USD__c == 2000, 'B populated after move');
    }

    @isTest static void bulkViaBatch() {
        FirmRollupTriggerGuard.bypass = true;
        List<Account> firms = new List<Account>();
        for (Integer i = 0; i < 20; i++) firms.add(new Account(Name = 'BulkFirm ' + i, RecordTypeId = FirmRollupTestData.rt('Firm')));
        insert firms;
        Account off = FirmRollupTestData.office('BulkOffice');
        List<Opportunity> opps = new List<Opportunity>();
        for (Account f : firms) {
            for (Integer j = 0; j < 10; j++) {
                opps.add(FirmRollupTestData.newOpp(f.Id, off.Id, 'Closed Won', 'New Business', 100, 'GBP', Date.today()));
            }
        }
        insert opps; // 200 opps across 20 firms

        Test.startTest();
        Database.executeBatch(new FirmRollupBatch(), 10);
        Test.stopTest();

        // counts are FX-independent -> deterministic even though async can't see injected rates
        Account r = [SELECT Firm_Won_Count_AllTime__c FROM Account WHERE Id = :firms[0].Id];
        System.assertEquals(10, r.Firm_Won_Count_AllTime__c.intValue(), 'each bulk firm has 10 won opps');
    }

    @isTest static void schedulableEnqueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('FSS test schedule', '0 0 2 * * ?', new FirmRollupBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'schedulable scheduled');
    }
}
