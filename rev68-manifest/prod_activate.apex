// REV-68 Step 7 activation (prod): schedule the sweeper + launch the count backfill.
String sched = System.schedule('LBR Interaction Convert Sweeper', '0 0 2 * * ?', new LBRInteractionConvertSweeper());
Id backfillJob = Database.executeBatch(new LBRInteractionCountBackfill(), 200);
System.debug('REV68_ACTIVATE sweeperCronId=' + sched + ' backfillJobId=' + backfillJob);
