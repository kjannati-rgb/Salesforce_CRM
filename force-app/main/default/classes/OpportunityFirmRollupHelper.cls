/**
 * FSS §5 — Opportunity trigger logic: enqueue affected firm(s) when a relevant field changes.
 * Re-parent safe (recompute BOTH old and new Ultimate_Account__c). Async-aware enqueue.
 */
public class OpportunityFirmRollupHelper {

    public static void handle(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Boolean isDelete) {
        if (FirmRollupTriggerGuard.isSuppressed()) return;
        Set<Id> firmIds = new Set<Id>();

        if (isDelete) {
            for (Opportunity o : oldMap.values()) if (o.Ultimate_Account__c != null) firmIds.add(o.Ultimate_Account__c);
        } else {
            for (Opportunity o : newList) {
                Opportunity old = (oldMap == null) ? null : oldMap.get(o.Id);
                if (old == null) {                                  // insert / undelete
                    if (o.Ultimate_Account__c != null) firmIds.add(o.Ultimate_Account__c);
                } else if (isRelevantChange(o, old)) {               // update
                    if (o.Ultimate_Account__c != null) firmIds.add(o.Ultimate_Account__c);
                    if (old.Ultimate_Account__c != null) firmIds.add(old.Ultimate_Account__c);
                }
            }
        }
        enqueue(firmIds);
    }

    static Boolean isRelevantChange(Opportunity o, Opportunity old) {
        return o.StageName != old.StageName
            || o.Amount != old.Amount
            || o.CurrencyIsoCode != old.CurrencyIsoCode
            || o.Ultimate_Account__c != old.Ultimate_Account__c
            || o.CloseDate != old.CloseDate
            || o.Type != old.Type;
    }

    /** Shared enqueue: async-aware (direct recompute if already async or batch). */
    public static void enqueue(Set<Id> firmIds) {
        if (firmIds == null) return;
        firmIds.remove(null);
        if (firmIds.isEmpty()) return;
        if (System.isBatch() || System.isFuture() || System.isQueueable()) {
            FirmRollupService.recalculateFirms(firmIds);
        } else {
            System.enqueueJob(new FirmRollupQueueable(firmIds));
        }
    }
}
