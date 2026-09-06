/**
 * Schedules RenewalReconciliationBatch to run nightly, unscoped (all activated orders
 * org-wide, no date/brand/family/account filter) - the ongoing permanent fix, as opposed
 * to a one-off scoped backfill run kicked off manually with a specific
 * RenewalReconciliationScope.
 */
public with sharing class RenewalReconciliationSchedulable implements Schedulable {

    public static final String NIGHTLY_CRON = '0 0 2 * * ?'; // 02:00 every day

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RenewalReconciliationBatch(new RenewalReconciliationScope()), 200);
    }

    /**
     * @return the Id of the scheduled job, for confirmation/logging
     * @example Id jobId = RenewalReconciliationSchedulable.scheduleNightly();
     */
    public static Id scheduleNightly() {
        return System.schedule('Renewal Reconciliation - Nightly', NIGHTLY_CRON, new RenewalReconciliationSchedulable());
    }
}
