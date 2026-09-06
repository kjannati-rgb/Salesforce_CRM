String jobId = System.schedule('Account Plan Snapshots', '0 0 2 ? * MON', new PlanSnapshotSchedule());
System.debug('SCHEDULED_JOB_ID=' + jobId);
