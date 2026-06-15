@isTest
private class WhitespaceAllocationServiceTest {

    private static Id rtId(String devName) {
        return Schema.SObjectType.Account_Plan__c
            .getRecordTypeInfosByDeveloperName().get(devName).getRecordTypeId();
    }

    private static Map<Id, Whitespace_Cell__c> cellsByFamily(Id planId) {
        Map<Id, Whitespace_Cell__c> byFam = new Map<Id, Whitespace_Cell__c>();
        // (test helper for single-cell-per-family scenarios only)
        for (Whitespace_Cell__c c : [
            SELECT Id, Product_Family__c, Expected_Revenue__c
            FROM Whitespace_Cell__c WHERE Account_Plan__c = :planId
        ]) {
            byFam.put(c.Product_Family__c, c);
        }
        return byFam;
    }

    /**
     * Law-firm plan, two families across three equal-weight nodes.
     * Exercises: benchmark math, even-weight allocation, rounding-remainder pin,
     * saturation (gap = 0), coverage recompute, roll-up reflection, and idempotency.
     */
    @isTest
    static void allocatesGapAcrossNodesAndPinsRemainder() {
        Plan_Product_Family__c famA = new Plan_Product_Family__c(
            Name = 'Family A', Relevant_Law_Firm__c = true, Relevant_Corporate__c = true,
            Sort_Order__c = 1, Benchmark_ARR_Per_Seat_Law_Firm__c = 1000);
        Plan_Product_Family__c famB = new Plan_Product_Family__c(
            Name = 'Family B', Relevant_Law_Firm__c = true, Relevant_Corporate__c = true,
            Sort_Order__c = 2, Benchmark_ARR_Per_Seat_Law_Firm__c = 500);
        insert new List<Plan_Product_Family__c>{ famA, famB };

        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Law Plan', RecordTypeId = rtId('Law_Firm'),
            Plan_Tier__c = 'T1', SoW_Denominator__c = 100);
        insert plan;

        List<Whitespace_Cell__c> cells = new List<Whitespace_Cell__c>();
        Integer i = 0;
        for (String node : new List<String>{ 'n1', 'n2', 'n3' }) {
            cells.add(new Whitespace_Cell__c(
                Account_Plan__c = plan.Id, Product_Family__c = famA.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = node, Node_Label__c = node,
                State__c = 'White_Space', ARR__c = 0,
                External_Key__c = plan.Id + '|A|' + node));
            cells.add(new Whitespace_Cell__c(
                Account_Plan__c = plan.Id, Product_Family__c = famB.Id,
                Node_Type__c = 'Office_Subsidiary', Node_Key__c = node, Node_Label__c = node,
                State__c = 'Owned_Healthy', ARR__c = 30000, Expected_Revenue__c = 999,
                External_Key__c = plan.Id + '|B|' + node));
            i++;
        }
        insert cells;

        Map<String, Decimal> mult = new Map<String, Decimal>{ 'T1' => 1.0 };

        Test.startTest();
        Integer changed = WhitespaceAllocationService.allocate(new Set<Id>{ plan.Id }, mult);
        Test.stopTest();

        // Three Family A white-space cells get allocations; three saturated Family B cells are
        // cleared from their stale 999 to 0 -> six rows change in total.
        System.assertEquals(6, changed, 'three allocated + three stale cells cleared');

        // Family A: gap = 1000 * 100 = 100,000, split across three equal-weight nodes.
        List<Decimal> aVals = new List<Decimal>();
        Decimal aSum = 0;
        Integer pinned = 0;
        for (Whitespace_Cell__c c : [
            SELECT Expected_Revenue__c FROM Whitespace_Cell__c
            WHERE Account_Plan__c = :plan.Id AND Product_Family__c = :famA.Id
        ]) {
            aVals.add(c.Expected_Revenue__c);
            aSum += c.Expected_Revenue__c;
            System.assert(c.Expected_Revenue__c == 33333.33 || c.Expected_Revenue__c == 33333.34,
                'each share is ~one third: ' + c.Expected_Revenue__c);
            if (c.Expected_Revenue__c == 33333.34) pinned++;
        }
        System.assertEquals(100000, aSum, 'allocations sum exactly to the family gap');
        System.assertEquals(1, pinned, 'rounding remainder pinned to exactly one cell');

        // Family B: benchmark 50,000 < owned 90,000 -> gap 0 -> no headroom.
        for (Whitespace_Cell__c c : [
            SELECT Expected_Revenue__c FROM Whitespace_Cell__c
            WHERE Account_Plan__c = :plan.Id AND Product_Family__c = :famB.Id
        ]) {
            System.assertEquals(0, c.Expected_Revenue__c, 'saturated family has zero headroom');
        }

        // Roll-ups + coverage reflect the engine.
        Account_Plan__c after = [
            SELECT Headroom__c, Total_ARR__c, Family_Coverage_Pct__c
            FROM Account_Plan__c WHERE Id = :plan.Id];
        System.assertEquals(100000, after.Headroom__c, 'Headroom roll-up = total gap');
        System.assertEquals(90000, after.Total_ARR__c, 'Total ARR roll-up = owned');
        System.assertEquals(50.0, after.Family_Coverage_Pct__c, 'coverage = present(3)/applicable(6)');

        // Idempotent: same inputs -> nothing changes.
        Integer again = WhitespaceAllocationService.allocate(new Set<Id>{ plan.Id }, mult);
        System.assertEquals(0, again, 'second run is a no-op');
    }

    /**
     * Corporate plan, single greenfield node. Exercises the corporate benchmark branch,
     * the tier multiplier (< 1), and the zero-owned-node weight floor.
     */
    @isTest
    static void allocatesGreenfieldCorporateWithTierMultiplier() {
        Plan_Product_Family__c famC = new Plan_Product_Family__c(
            Name = 'Family C', Relevant_Law_Firm__c = true, Relevant_Corporate__c = true,
            Sort_Order__c = 1, Benchmark_ARR_Per_Seat_Corporate__c = 2000);
        insert famC;

        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Corp Plan', RecordTypeId = rtId('Corporate'),
            Plan_Tier__c = 'T2', SoW_Denominator__c = 10);
        insert plan;

        insert new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = famC.Id,
            Node_Type__c = 'Practice_Function', Node_Key__c = 'legal', Node_Label__c = 'Legal',
            State__c = 'White_Space', ARR__c = 0, External_Key__c = plan.Id + '|C|legal');

        Test.startTest();
        Integer changed = WhitespaceAllocationService.allocate(
            new Set<Id>{ plan.Id }, new Map<String, Decimal>{ 'T2' => 0.85 });
        Test.stopTest();

        // benchmark = 2000 * 10 * 0.85 = 17,000, all to the single greenfield cell.
        System.assertEquals(1, changed, 'one cell allocated');
        System.assertEquals(17000, cellsByFamily(plan.Id).get(famC.Id).Expected_Revenue__c,
            'tier-scaled corporate benchmark allocated to greenfield node');
    }

    @isTest
    static void handlesEmptyAndCelllessInputs() {
        System.assertEquals(0, WhitespaceAllocationService.allocate(null), 'null is a no-op');
        System.assertEquals(0, WhitespaceAllocationService.allocate(new Set<Id>()), 'empty is a no-op');

        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Empty Plan', RecordTypeId = rtId('Law_Firm'),
            Plan_Tier__c = 'T1', SoW_Denominator__c = 50);
        insert plan;
        System.assertEquals(0, WhitespaceAllocationService.allocate(new Set<Id>{ plan.Id }),
            'plan with no cells is a no-op');
    }

    @isTest
    static void invocableEntryPointRuns() {
        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'Family I', Relevant_Law_Firm__c = true, Sort_Order__c = 1,
            Benchmark_ARR_Per_Seat_Law_Firm__c = 800);
        insert fam;
        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Invocable Plan', RecordTypeId = rtId('Law_Firm'),
            Plan_Tier__c = 'T1', SoW_Denominator__c = 20);
        insert plan;
        insert new Whitespace_Cell__c(
            Account_Plan__c = plan.Id, Product_Family__c = fam.Id,
            Node_Type__c = 'Office_Subsidiary', Node_Key__c = 'hq', Node_Label__c = 'HQ',
            State__c = 'White_Space', ARR__c = 0, External_Key__c = plan.Id + '|I|hq');

        Test.startTest();
        List<Integer> result = WhitespaceAllocationService.allocateInvocable(new List<Id>{ plan.Id });
        Test.stopTest();

        System.assertEquals(1, result.size(), 'one result per invocation');
        System.assert(result[0] >= 0, 'allocation count returned');
    }
}
