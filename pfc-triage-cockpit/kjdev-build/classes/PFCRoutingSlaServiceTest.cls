@IsTest
private class PFCRoutingSlaServiceTest {

    private static Id triageQueueId() {
        return [
            SELECT Id FROM Group
            WHERE DeveloperName = :PFCRoutingSlaService.QUEUE_DEV_NAME AND Type = 'Queue'
            LIMIT 1
        ].Id;
    }

    private static List<Pardot_Form_Completion__c> makeQueuedPfcs(Integer count) {
        Id queueId = triageQueueId();
        List<Pardot_Form_Completion__c> pfcs = new List<Pardot_Form_Completion__c>();
        for (Integer i = 0; i < count; i++) {
            pfcs.add(new Pardot_Form_Completion__c(
                Name = 'SLA Test ' + i,
                Sales_Stage__c = 'New',
                OwnerId = queueId
            ));
        }
        insert pfcs;
        return pfcs;
    }

    @IsTest
    static void flagsOverdueRecordsAndIsIdempotent() {
        List<Pardot_Form_Completion__c> pfcs = makeQueuedPfcs(5);

        Test.startTest();
        PFCRoutingSlaService.SweepResult first = PFCRoutingSlaService.run(0, null);
        PFCRoutingSlaService.SweepResult second = PFCRoutingSlaService.run(0, null);
        Test.stopTest();

        System.assertEquals(5, first.flagged, 'threshold 0 should flag every queue-owned record');
        System.assertEquals(0, second.flagged, 'second sweep must not re-flag');
        System.assertEquals(5, [
            SELECT COUNT() FROM Pardot_Form_Completion__c
            WHERE Id IN :pfcs AND Routing_Overdue__c = true
        ]);
    }

    @IsTest
    static void freshRecordsAreNotFlaggedAtRealThreshold() {
        makeQueuedPfcs(3);

        Test.startTest();
        PFCRoutingSlaService.SweepResult result = PFCRoutingSlaService.run(4, null);
        Test.stopTest();

        System.assertEquals(3, result.candidates, 'queue-owned records should be candidates');
        System.assertEquals(0, result.flagged, 'records created seconds ago must not breach a 4h SLA');
    }

    @IsTest
    static void userOwnedRecordsAreIgnored() {
        insert new Pardot_Form_Completion__c(
            Name = 'User-owned',
            Sales_Stage__c = 'New',
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        PFCRoutingSlaService.SweepResult result = PFCRoutingSlaService.run(0, null);
        Test.stopTest();

        System.assertEquals(0, result.candidates, 'user-owned records are not sweep candidates');
    }

    @IsTest
    static void postsChatterDigestWhenGroupExists() {
        CollaborationGroup grp = new CollaborationGroup(
            Name = 'PFC SLA Test Group',
            CollaborationType = 'Private'
        );
        insert grp;
        makeQueuedPfcs(2);

        Test.startTest();
        PFCRoutingSlaService.SweepResult result = PFCRoutingSlaService.run(0, 'PFC SLA Test Group');
        Test.stopTest();

        System.assertEquals(2, result.flagged);
        System.assert(result.chatterPosted, 'digest should post to the existing group');
        System.assertEquals(1, [SELECT COUNT() FROM FeedItem WHERE ParentId = :grp.Id]);
    }

    @IsTest
    static void missingChatterGroupFlagsButDoesNotPost() {
        makeQueuedPfcs(1);

        Test.startTest();
        PFCRoutingSlaService.SweepResult result = PFCRoutingSlaService.run(0, 'No Such Group Zzz');
        Test.stopTest();

        System.assertEquals(1, result.flagged, 'flagging must not depend on Chatter');
        System.assert(!result.chatterPosted);
    }

    @IsTest
    static void bulkTwoHundredRecords() {
        makeQueuedPfcs(200);

        Test.startTest();
        PFCRoutingSlaService.SweepResult result = PFCRoutingSlaService.run(0, null);
        Test.stopTest();

        System.assertEquals(200, result.flagged, 'sweep must be bulk-safe at 200 records');
    }

    @IsTest
    static void schedulableRunsCmdtPath() {
        makeQueuedPfcs(1);

        Test.startTest();
        String jobId = System.schedule(
            'PFC SLA Sweep Test',
            '0 0 0 1 1 ? 2099',
            new PFCRoutingSlaSweepSchedulable()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        // CMDT path uses the real 4h threshold: fresh test records stay unflagged.
        System.assertEquals(0, [
            SELECT COUNT() FROM Pardot_Form_Completion__c WHERE Routing_Overdue__c = true
        ]);
    }
}
