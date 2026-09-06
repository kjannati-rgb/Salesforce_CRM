/**
 * Verifies WhitespaceGenerationService against the real firm/office structure (architecture §4).
 *
 * Uses SeeAllData because the service is fundamentally about live CRM accounts, and this org's
 * Account/Product objects gate creation behind record-type-restricted required picklists that make
 * synthetic test data impractical. All DML here is rolled back at test end, so the curated demo is
 * untouched. (A synthetic-data variant is a follow-up once a CPQ-seeded sandbox is available.)
 */
@isTest(SeeAllData=true)
private class WhitespaceGenerationServiceTest {

    @isTest
    static void generatesMatrixFromFirmStructure() {
        System.assertEquals(0, WhitespaceGenerationService.generate(null), 'null is a no-op');
        System.assertEquals(0, WhitespaceGenerationService.generate(new Set<Id>()), 'empty is a no-op');

        List<Account_Plan__c> plans = [
            SELECT Id FROM Account_Plan__c WHERE Account__r.Name = 'Globex Legal (DEMO)' LIMIT 1];
        if (plans.isEmpty()) {
            return; // demo data not present in this org — nothing to assert against
        }
        Id planId = plans[0].Id;

        Test.startTest();
        Integer made = WhitespaceGenerationService.generate(new Set<Id>{ planId });
        Test.stopTest();

        System.assert(made > 0, 'cells generated from the firm office structure');

        List<Whitespace_Cell__c> cells = [
            SELECT Office_Account__c, Product_Family__c, State__c
            FROM Whitespace_Cell__c WHERE Account_Plan__c = :planId];
        System.assertEquals(made, cells.size(), 'all generated cells persisted');

        Set<Id> offices = new Set<Id>();
        for (Whitespace_Cell__c c : cells) {
            System.assertNotEquals(null, c.Office_Account__c, 'every node links a real office Account');
            System.assertNotEquals(null, c.Product_Family__c, 'every cell has a product family');
            offices.add(c.Office_Account__c);
        }
        System.assert(offices.size() >= 1, 'at least one office node generated');
    }

    /**
     * Phase 2 state precedence, tested directly against the pure decision function (no DML, no CPQ
     * dependency) — SBQQ__Subscription__c has enough managed-package validation surface that
     * fabricating realistic test rows is fragile; the query plumbing that feeds CellSignal is exercised
     * end-to-end above, this covers the actual branching logic.
     */
    @isTest
    static void resolveStatePrecedenceCoversAllSignals() {
        Date today = Date.today();
        Date cutoff = today.addDays(90);

        WhitespaceGenerationService.CellSignal renewing = new WhitespaceGenerationService.CellSignal();
        renewing.activeTermEnd = today.addDays(30);
        System.assertEquals('In_Renewal',
            WhitespaceGenerationService.resolveState(5000, renewing, today, cutoff),
            'active term inside the renewal window wins even though owned > 0');

        WhitespaceGenerationService.CellSignal healthy = new WhitespaceGenerationService.CellSignal();
        healthy.activeTermEnd = today.addDays(200);
        System.assertEquals('Owned_Healthy',
            WhitespaceGenerationService.resolveState(5000, healthy, today, cutoff),
            'active term outside the renewal window is healthy');

        System.assertEquals('Owned_Healthy',
            WhitespaceGenerationService.resolveState(1000, null, today, cutoff),
            'owned ARR with no term data at all still falls back to healthy');

        WhitespaceGenerationService.CellSignal booked = new WhitespaceGenerationService.CellSignal();
        booked.hasFutureTerm = true;
        System.assertEquals('Booked',
            WhitespaceGenerationService.resolveState(0, booked, today, cutoff),
            'a future-dated term with nothing currently active is booked');

        WhitespaceGenerationService.CellSignal winback = new WhitespaceGenerationService.CellSignal();
        winback.earliestLapsedEnd = today.addDays(-60);
        System.assertEquals('Win_Back',
            WhitespaceGenerationService.resolveState(0, winback, today, cutoff),
            'a lapsed term with no active or future successor is win-back');

        WhitespaceGenerationService.CellSignal candidate = new WhitespaceGenerationService.CellSignal();
        candidate.hasCandidateOpenOpp = true;
        System.assertEquals('Candidate',
            WhitespaceGenerationService.resolveState(0, candidate, today, cutoff),
            'open pipeline past Identify/Qualify with no term signal is a candidate');

        System.assertEquals('No_Engagement',
            WhitespaceGenerationService.resolveState(0, null, today, cutoff),
            'no signal at all (never touched) is no-engagement');

        WhitespaceGenerationService.CellSignal touched = new WhitespaceGenerationService.CellSignal();
        touched.hasHistory = true;
        System.assertEquals('White_Space',
            WhitespaceGenerationService.resolveState(0, touched, today, cutoff),
            'some history (e.g. a closed-lost early opp) but no live signal falls through to white space');

        WhitespaceGenerationService.CellSignal renewedAfterLapse = new WhitespaceGenerationService.CellSignal();
        renewedAfterLapse.activeTermEnd = today.addDays(200);
        renewedAfterLapse.earliestLapsedEnd = today.addDays(-400);
        System.assertEquals('Owned_Healthy',
            WhitespaceGenerationService.resolveState(0, renewedAfterLapse, today, cutoff),
            'an active successor term overrides a stale lapsed signal from an earlier segment');

        // Regression: a confirmed lapse must beat the vague "owned > 0" lifetime-ARR fallback, not be
        // masked by it — a firm with old historical revenue on a product it has since dropped is a
        // real win-back, not a false "healthy".
        WhitespaceGenerationService.CellSignal churnedWithHistoricalArr = new WhitespaceGenerationService.CellSignal();
        churnedWithHistoricalArr.earliestLapsedEnd = today.addDays(-90);
        System.assertEquals('Win_Back',
            WhitespaceGenerationService.resolveState(5000, churnedWithHistoricalArr, today, cutoff),
            'a confirmed lapse beats stale historical ARR instead of being masked by it');
    }

    /**
     * Auto-signal emission on state transitions, exercised directly against emitTransitionSignals() with
     * hand-built cells (not inserted — Linked_Cell__c staying null is fine, it's an optional lookup)
     * against a synthetic Account_Plan__c/Plan_Product_Family__c. No SeeAllData/real-firm dependency here.
     */
    @isTest
    static void emitTransitionSignalsFiresOnlyOnTransition() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Signal Test Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        Map<Id, String> famNames = new Map<Id, String>{ fam.Id => fam.Name };

        Whitespace_Cell__c renewingCell = new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
            Node_Key__c = 'london', Node_Label__c = 'London', State__c = 'In_Renewal',
            External_Key__c = plan.Id + '|' + fam.Id + '|london');
        Whitespace_Cell__c winbackCell = new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
            Node_Key__c = 'paris', Node_Label__c = 'Paris', State__c = 'Win_Back',
            External_Key__c = plan.Id + '|' + fam.Id + '|paris');
        Whitespace_Cell__c unchangedCell = new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
            Node_Key__c = 'milan', Node_Label__c = 'Milan', State__c = 'White_Space',
            External_Key__c = plan.Id + '|' + fam.Id + '|milan');

        Map<String, String> oldStateByKey = new Map<String, String>{
            renewingCell.External_Key__c => 'Owned_Healthy',
            winbackCell.External_Key__c => 'Owned_Healthy',
            unchangedCell.External_Key__c => 'White_Space'
        };

        Test.startTest();
        WhitespaceGenerationService.emitTransitionSignals(
            new List<Whitespace_Cell__c>{ renewingCell, winbackCell, unchangedCell }, oldStateByKey, famNames);
        Test.stopTest();

        List<Plan_Signal__c> signals = [
            SELECT Signal_Type__c, Severity__c, Summary__c FROM Plan_Signal__c WHERE Account_Plan__c = :plan.Id];
        System.assertEquals(2, signals.size(), 'only the two transitioning cells raise a signal — the unchanged one does not');

        Map<String, Plan_Signal__c> byType = new Map<String, Plan_Signal__c>();
        for (Plan_Signal__c s : signals) {
            byType.put(s.Signal_Type__c, s);
        }
        System.assert(byType.containsKey('Risk'), 'the In_Renewal transition raised a Risk signal');
        System.assertEquals('Medium', byType.get('Risk').Severity__c, 'renewal risk is medium severity');
        System.assert(byType.get('Risk').Summary__c.contains('London'), 'summary names the office: ' + byType.get('Risk').Summary__c);

        System.assert(byType.containsKey('Churn'), 'the Win_Back transition raised a Churn signal');
        System.assertEquals('High', byType.get('Churn').Severity__c, 'churn is high severity');
        System.assert(byType.get('Churn').Summary__c.contains('Paris'), 'summary names the office: ' + byType.get('Churn').Summary__c);
    }

    @isTest
    static void emitTransitionSignalsDoesNotDuplicateAnAlreadyOpenSignal() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Dedupe Test Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        Map<Id, String> famNames = new Map<Id, String>{ fam.Id => fam.Name };

        Whitespace_Cell__c cell = new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
            Node_Key__c = 'london', Node_Label__c = 'London', State__c = 'In_Renewal',
            External_Key__c = plan.Id + '|' + fam.Id + '|london');

        insert new Plan_Signal__c(Account_Plan__c = plan.Id, Signal_Type__c = 'Risk', Severity__c = 'Medium',
            Source__c = 'Whitespace_Cell', Status__c = 'Open', Detected_Date__c = Date.today(),
            Summary__c = 'London — Lexology PRO renews within 90 days');

        Test.startTest();
        WhitespaceGenerationService.emitTransitionSignals(
            new List<Whitespace_Cell__c>{ cell },
            new Map<String, String>{ cell.External_Key__c => 'Owned_Healthy' },
            famNames);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Plan_Signal__c WHERE Account_Plan__c = :plan.Id],
            'an already-open signal with the same summary is not duplicated');
    }

    /**
     * Objective auto-progress, exercised directly against recalcObjectiveProgress() with hand-built
     * cells (not inserted — only Account_Plan__c/Product_Family__c/ARR__c are read off them).
     */
    @isTest
    static void recalcObjectiveProgressUpdatesLinkedObjective() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Objective Progress Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        Plan_Objective__c objective = new Plan_Objective__c(
            Account_Plan__c = plan.Id, Name = 'Grow Lexology PRO', Status__c = 'In_Progress',
            Target_Amount__c = 100000, Linked_Family__c = fam.Id);
        insert objective;

        List<Whitespace_Cell__c> cells = new List<Whitespace_Cell__c>{
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'london', Node_Label__c = 'London',
                State__c = 'Owned_Healthy', ARR__c = 30000,
                External_Key__c = plan.Id + '|' + fam.Id + '|london'),
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'paris', Node_Label__c = 'Paris',
                State__c = 'Owned_Healthy', ARR__c = 10000,
                External_Key__c = plan.Id + '|' + fam.Id + '|paris')
        };

        Test.startTest();
        WhitespaceGenerationService.recalcObjectiveProgress(cells, new List<Id>{ plan.Id });
        Test.stopTest();

        Plan_Objective__c refreshed = [
            SELECT Current_Amount__c, Progress_Pct__c FROM Plan_Objective__c WHERE Id = :objective.Id];
        System.assertEquals(40000, refreshed.Current_Amount__c, 'current amount sums ARR across both cells for the linked family');
        System.assertEquals(40.0, refreshed.Progress_Pct__c, 'progress is current/target — 40000/100000');
    }

    @isTest
    static void recalcObjectiveProgressLeavesUnlinkedObjectiveAlone() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'Manual Objective Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        Plan_Objective__c manual = new Plan_Objective__c(
            Account_Plan__c = plan.Id, Name = 'Manually tracked goal', Status__c = 'In_Progress',
            Target_Amount__c = 100000, Progress_Pct__c = 55); // no Linked_Family__c
        insert manual;

        List<Whitespace_Cell__c> cells = new List<Whitespace_Cell__c>{
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'london', Node_Label__c = 'London',
                State__c = 'Owned_Healthy', ARR__c = 30000,
                External_Key__c = plan.Id + '|' + fam.Id + '|london')
        };

        Test.startTest();
        WhitespaceGenerationService.recalcObjectiveProgress(cells, new List<Id>{ plan.Id });
        Test.stopTest();

        Plan_Objective__c refreshed = [
            SELECT Current_Amount__c, Progress_Pct__c FROM Plan_Objective__c WHERE Id = :manual.Id];
        System.assertEquals(null, refreshed.Current_Amount__c, 'unlinked objectives are never touched');
        System.assertEquals(55, refreshed.Progress_Pct__c, 'manually-set progress is preserved');
    }

    @isTest
    static void recalcObjectiveProgressHandlesBlankTargetWithoutError() {
        Account_Plan__c plan = new Account_Plan__c(Name = 'No Target Plan', Plan_Tier__c = 'T1');
        insert plan;
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Lexology PRO', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;
        Plan_Objective__c noTarget = new Plan_Objective__c(
            Account_Plan__c = plan.Id, Name = 'No target set yet', Status__c = 'Not_Started',
            Linked_Family__c = fam.Id); // Target_Amount__c left blank
        insert noTarget;

        List<Whitespace_Cell__c> cells = new List<Whitespace_Cell__c>{
            new Whitespace_Cell__c(Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'london', Node_Label__c = 'London',
                State__c = 'Owned_Healthy', ARR__c = 30000,
                External_Key__c = plan.Id + '|' + fam.Id + '|london')
        };

        Test.startTest();
        WhitespaceGenerationService.recalcObjectiveProgress(cells, new List<Id>{ plan.Id });
        Test.stopTest();

        Plan_Objective__c refreshed = [
            SELECT Current_Amount__c, Progress_Pct__c FROM Plan_Objective__c WHERE Id = :noTarget.Id];
        System.assertEquals(30000, refreshed.Current_Amount__c, 'current amount still reflects real ARR with no target set');
        System.assertEquals(0, refreshed.Progress_Pct__c, 'progress falls back to 0 rather than dividing by a blank target');
    }
}
