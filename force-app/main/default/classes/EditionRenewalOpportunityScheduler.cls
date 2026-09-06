/**
 * Schedules EditionRenewalOpportunityBatch nightly, mirroring RenewalReconciliationSchedulable's
 * pattern. Runs after RenewalReconciliationSchedulable's own window so the two nightly jobs do
 * not contend over the same Closed Won population at the same minute.
 *
 * Originally scoped to "WTR 1000" only. Extended to cover every other product family in the
 * backlog a PROD dry run turned up (IAM Patent 1000, GAR 100, Latin Lawyer LL250, IAM Strategy
 * 300, WTR Global Leaders, IAM Global Leaders, Client Choice Featured Expert Profile) - only
 * Lexology Index (534 lines, by far the largest single family) stays out, as a deliberately
 * separate decision.
 */
public class EditionRenewalOpportunityScheduler implements Schedulable {

    public static final String NIGHTLY_CRON = '0 30 2 * * ?';
    public static final String SCOPE_EXCLUDE_PRODUCT_NAME_PREFIX = 'Lexology Index';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new EditionRenewalOpportunityBatch(null, SCOPE_EXCLUDE_PRODUCT_NAME_PREFIX), 200);
    }

    public static Id scheduleNightly() {
        return System.schedule('Edition Renewal Opportunity Creation - Nightly', NIGHTLY_CRON, new EditionRenewalOpportunityScheduler());
    }
}
