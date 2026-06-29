/**
 * FSS §5 — nightly reconcile + one-time backfill. Essential even with no record edits: the
 * CFY/PFY/T12M windows and the dated FX rates shift over time. Small scope (10 firms) keeps each
 * execute's per-firm aggregates governor-safe. Schedule ~02:00 Europe/London.
 */
public class FirmRollupBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Firm'
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
