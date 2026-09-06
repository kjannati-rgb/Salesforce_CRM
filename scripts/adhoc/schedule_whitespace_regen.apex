String jobId = System.schedule('Account Plan White-Space Regen', '0 0 3 * * ?', new WhitespaceGenerationSchedule());
System.debug('SCHEDULED_JOB_ID=' + jobId);
