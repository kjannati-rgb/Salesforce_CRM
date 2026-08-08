/**
 * FSS §5 — nightly reconcile + one-time backfill. Essential even with no record edits: the
 * CFY/PFY/T12M windows and the dated FX rates shift over time. Small scope (10 firms) keeps each
 * execute's per-firm aggregates governor-safe. Schedule ~02:00 Europe/London.
 */
public class FirmRollupBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Scope to firms with won/cancelled opportunities — a Firm with none has null headline +
        // group rollups with nothing to recompute, so scanning the whole Account table (300k+ Firm
        // records in prod/full-copy) is wasted work. A single top-level semi-join is the only form
        // the platform allows (semi-joins can't be OR'd). Sub-only firms (active subs but no won
        // opp — a small set) are maintained in real time by the Subscription trigger; re-parents
        // and deletes are likewise trigger-handled.
        return Database.getQueryLocator([
            SELECT Id FROM Account
            WHERE RecordType.DeveloperName = 'Firm'
              AND Id IN (SELECT Ultimate_Account__c FROM Opportunity
                         WHERE StageName IN (:FirmRollupService.STAGE_WON, :FirmRollupService.STAGE_CANC))
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> firmIds = new Set<Id>();
        for (Account a : scope) firmIds.add(a.Id);
        FirmRollupService.recalculateFirms(firmIds);
    }

    public void finish(Database.BatchableContext bc) { /* no-op */ }

    // Schedulable entry point
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new FirmRollupBatch(), 10);
    }
}
