/**
 * LBRInteractionCountHandler
 * --------------------------
 * Maintains Contact.Count_of_LBR_Interactions__c (the Number field that replaced the
 * former roll-up summary once Contact__c became a Lookup, REV-68). Recomputes the count
 * for every Contact touched by an LBR_Interactions__c insert/update/delete/undelete.
 * Bulk-safe: one aggregate query and one DML regardless of trigger volume.
 */
public with sharing class LBRInteractionCountHandler {

    public static void handle(List<LBR_Interactions__c> newList, Map<Id, LBR_Interactions__c> oldMap) {
        Set<Id> contactIds = new Set<Id>();
        if (newList != null) {
            for (LBR_Interactions__c i : newList) {
                if (i.Contact__c != null) contactIds.add(i.Contact__c);
            }
        }
        if (oldMap != null) {
            for (LBR_Interactions__c i : oldMap.values()) {
                if (i.Contact__c != null) contactIds.add(i.Contact__c);
            }
        }
        if (contactIds.isEmpty()) return;

        Map<Id, Decimal> counts = new Map<Id, Decimal>();
        for (Id cid : contactIds) counts.put(cid, 0);
        for (AggregateResult ar : [
            SELECT Contact__c cid, COUNT(Id) cnt
            FROM LBR_Interactions__c
            WHERE Contact__c IN :contactIds
            GROUP BY Contact__c
        ]) {
            counts.put((Id) ar.get('cid'), (Decimal) ar.get('cnt'));
        }

        List<Contact> updates = new List<Contact>();
        for (Id cid : counts.keySet()) {
            updates.add(new Contact(Id = cid, Count_of_LBR_Interactions__c = counts.get(cid)));
        }
        if (!updates.isEmpty()) update updates;
    }
}
