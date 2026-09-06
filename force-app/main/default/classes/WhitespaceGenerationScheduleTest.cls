@isTest
private class WhitespaceGenerationScheduleTest {

    @isTest
    static void scheduleRunsWithoutError() {
        Test.startTest();
        new WhitespaceGenerationSchedule().execute(null);
        Test.stopTest();
        // No active plans exist in this synthetic test context, so generate() is a safe no-op —
        // this just proves the scheduled entry point wires through cleanly, same shape as
        // PlanSnapshotServiceTest.captureAllActiveAndScheduleRun.
        System.assert(true, 'schedule executed without throwing');
    }

    @isTest
    static void canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule('Account Plan White-Space Regen Test',
            '0 0 3 * * ?', new WhitespaceGenerationSchedule());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'the job was scheduled');
    }
}
