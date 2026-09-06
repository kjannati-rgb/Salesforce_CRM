/**
 * LBRInteractionCountBackfill
 * ---------------------------
 * One-off batch to populate Contact.Count_of_LBR_Interactions__c after the roll-up summary
 * was replaced by the trigger-maintained Number field (REV-68). The trigger only updates a
 * Contact when one of its interactions changes, so existing Contacts need a one-time recompute.
 *
 *   Database.executeBatch(new LBRInteractionCountBackfill(), 200);
 */
public with sharing class LBRInteractionCountBackfill implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Only Contacts that actually have interactions need updating.
        return Database.getQueryLocator([
            SELECT Id FROM Contact
            WHERE Id IN (SELECT Contact__c FROM LBR_Interactions__c WHERE Contact__c != null)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        Set<Id> contactIds = (new Map<Id, Contact>(scope)).keySet();
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

    public void finish(Database.BatchableContext bc) {}
}
