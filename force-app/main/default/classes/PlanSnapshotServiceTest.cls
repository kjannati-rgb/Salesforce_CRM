@isTest
private class PlanSnapshotServiceTest {

    @isTest
    static void capturesMetricsAndIsIdempotent() {
        Account_Plan__c plan = new Account_Plan__c(
            Name = 'Snap Plan', Plan_Tier__c = 'T1', Plan_Status__c = 'Active');
        insert plan;

        Plan_Product_Family__c fam = new Plan_Product_Family__c(
            Name = 'F', Relevant_Law_Firm__c = true, Sort_Order__c = 1);
        insert fam;

        insert new List<Whitespace_Cell__c>{
            new Whitespace_Cell__c(
                Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
                Node_Key__c = 'a', Node_Label__c = 'A', State__c = 'Owned_Healthy', ARR__c = 100000,
                External_Key__c = plan.Id + '|' + fam.Id + '|a'),
            new Whitespace_Cell__c(
                Account_Plan__c = plan.Id, Product_Family__c = fam.Id, Node_Type__c = 'Office_Subsidiary',
                Node_Key__c = 'b', Node_Label__c = 'B', State__c = 'White_Space', ARR__c = 0,
                Expected_Revenue__c = 50000, External_Key__c = plan.Id + '|' + fam.Id + '|b')
        };

        Test.startTest();
        Integer first = PlanSnapshotService.capture(new Set<Id>{ plan.Id }, Date.today());
        Integer second = PlanSnapshotService.capture(new Set<Id>{ plan.Id }, Date.today()); // same day
        Test.stopTest();

        System.assertEquals(1, first, 'one snapshot captured');
        List<Plan_Snapshot__c> snaps = [
            SELECT Total_ARR__c, Headroom__c, Owned_ARR_Cells__c, Whitespace_Cells__c, Plan_Tier__c, Snapshot_Date__c
            FROM Plan_Snapshot__c WHERE Account_Plan__c = :plan.Id];
        System.assertEquals(1, snaps.size(), 'idempotent: still one snapshot for the day');
        System.assertEquals(100000, snaps[0].Total_ARR__c, 'captured owned-ARR roll-up');
        System.assertEquals(50000, snaps[0].Headroom__c, 'captured headroom roll-up');
        System.assertEquals(1, snaps[0].Owned_ARR_Cells__c, 'one owned cell');
        System.assertEquals(1, snaps[0].Whitespace_Cells__c, 'one white-space cell');
        System.assertEquals('T1', snaps[0].Plan_Tier__c, 'tier captured');
        System.assertEquals(Date.today(), snaps[0].Snapshot_Date__c, 'snapshot dated today');
    }

    @isTest
    static void captureAllActiveAndScheduleRun() {
        insert new Account_Plan__c(Name = 'Active Plan', Plan_Status__c = 'Active', Plan_Tier__c = 'T2');

        Test.startTest();
        Integer n = PlanSnapshotService.captureAllActive();
        new PlanSnapshotSchedule().execute(null);
        Test.stopTest();

        System.assert(n >= 1, 'captured at least the active plan');
        System.assert([SELECT COUNT() FROM Plan_Snapshot__c] >= 1, 'snapshots written');
    }

    @isTest
    static void handlesEmptyInputs() {
        System.assertEquals(0, PlanSnapshotService.capture(null, Date.today()), 'null is a no-op');
        System.assertEquals(0, PlanSnapshotService.capture(new Set<Id>(), Date.today()), 'empty is a no-op');
    }
}
