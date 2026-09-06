/**
 * Scheduled job that snapshots every active Account Plan (architecture §10). Schedule weekly/monthly:
 *   System.schedule('Account Plan Snapshots', '0 0 2 ? * MON', new PlanSnapshotSchedule());
 */
public with sharing class PlanSnapshotSchedule implements Schedulable {
    public void execute(SchedulableContext sc) {
        PlanSnapshotService.captureAllActive();
    }
}
