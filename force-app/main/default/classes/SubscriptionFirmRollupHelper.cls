/**
 * FSS §5 — SBQQ__Subscription__c trigger logic: enqueue affected firm(s) when start/end/terminated/
 * parent/value/currency change. Re-parent safe. Reuses OpportunityFirmRollupHelper.enqueue.
 */
public class SubscriptionFirmRollupHelper {

    public static void handle(List<SBQQ__Subscription__c> newList,
                              Map<Id, SBQQ__Subscription__c> oldMap, Boolean isDelete) {
        if (FirmRollupTriggerGuard.isSuppressed()) return;
        Set<Id> firmIds = new Set<Id>();

        if (isDelete) {
            for (SBQQ__Subscription__c s : oldMap.values()) if (s.Ultimate_Parent__c != null) firmIds.add(s.Ultimate_Parent__c);
        } else {
            for (SBQQ__Subscription__c s : newList) {
                SBQQ__Subscription__c old = (oldMap == null) ? null : oldMap.get(s.Id);
                if (old == null) {
                    if (s.Ultimate_Parent__c != null) firmIds.add(s.Ultimate_Parent__c);
                } else if (isRelevantChange(s, old)) {
                    if (s.Ultimate_Parent__c != null) firmIds.add(s.Ultimate_Parent__c);
                    if (old.Ultimate_Parent__c != null) firmIds.add(old.Ultimate_Parent__c);
                }
            }
        }
        OpportunityFirmRollupHelper.enqueue(firmIds);
    }

    static Boolean isRelevantChange(SBQQ__Subscription__c s, SBQQ__Subscription__c old) {
        return s.SBQQ__StartDate__c != old.SBQQ__StartDate__c
            || s.SBQQ__EndDate__c != old.SBQQ__EndDate__c
            || s.SBQQ__TerminatedDate__c != old.SBQQ__TerminatedDate__c
            || s.Ultimate_Parent__c != old.Ultimate_Parent__c
            || s.SBQQ__NetPrice__c != old.SBQQ__NetPrice__c
            || s.CurrencyIsoCode != old.CurrencyIsoCode;
    }
}
