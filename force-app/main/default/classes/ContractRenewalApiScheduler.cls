/**
 * Schedules ContractRenewalApiBatch nightly, scoped to "WTR 1000" - same scoping decision as
 * EditionRenewalOpportunityScheduler, offset by 15 minutes so the three nightly renewal jobs
 * (RenewalReconciliationBatch, EditionRenewalOpportunityBatch, this one) don't contend.
 */
public class ContractRenewalApiScheduler implements Schedulable {

    public static final String NIGHTLY_CRON = '0 45 2 * * ?';
    public static final String SCOPE_ORIGINAL_OPPORTUNITY_PREFIX = 'WTR 1000';

    public void execute(SchedulableContext sc) {
        /*
         * Chunk size of 1 is deliberate, not conservative padding: a live PROD run showed
         * SBQQ.RenewalAPI.renewContracts() enqueues its own internal Queueable job per call,
         * and Salesforce's queueable-jobs-per-transaction ceiling is low enough that a chunk
         * of more than one or two Contracts can collectively exceed it - which aborts the
         * whole chunk's execute() transaction (and every Contract in it) in a way this
         * class's own per-record try/catch cannot intercept, since the failure surfaces after
         * that code has already returned. One Contract per execute() avoids the collision.
         */
        Database.executeBatch(new ContractRenewalApiBatch(SCOPE_ORIGINAL_OPPORTUNITY_PREFIX), 1);
    }

    public static Id scheduleNightly() {
        return System.schedule('Contract Renewal API - Nightly', NIGHTLY_CRON, new ContractRenewalApiScheduler());
    }
}
