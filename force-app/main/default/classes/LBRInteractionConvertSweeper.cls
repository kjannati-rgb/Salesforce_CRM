/**
 * LBRInteractionConvertSweeper
 * ----------------------------
 * Daily safety net for REV-68. Catches LBR_Interactions__c still parented to a Lead
 * that has already been converted via ANY path that bypassed LeadConvertInvocable
 * (e.g. a standard convert button, an import, another automation). Re-parents them onto
 * the converted Contact/Account/Opportunity by reusing LBRInteractionReparentService.
 *
 * Schedule (e.g. daily 02:00):
 *   System.schedule('LBR Interaction Convert Sweeper',
 *                   '0 0 2 * * ?', new LBRInteractionConvertSweeper());
 */
public with sharing class LBRInteractionConvertSweeper
        implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Lead__c,
                   Lead__r.ConvertedContactId, Lead__r.ConvertedAccountId, Lead__r.ConvertedOpportunityId
            FROM LBR_Interactions__c
            WHERE Lead__c != null AND Lead__r.IsConverted = true
        ]);
    }

    public void execute(Database.BatchableContext bc, List<LBR_Interactions__c> scope) {
        Map<Id, LBRInteractionReparentService.ConvertedLead> byLead =
            new Map<Id, LBRInteractionReparentService.ConvertedLead>();
        for (LBR_Interactions__c li : scope) {
            if (li.Lead__c == null || li.Lead__r.ConvertedContactId == null) continue;
            byLead.put(li.Lead__c, new LBRInteractionReparentService.ConvertedLead(
                li.Lead__c,
                li.Lead__r.ConvertedContactId,
                li.Lead__r.ConvertedAccountId,
                li.Lead__r.ConvertedOpportunityId
            ));
        }
        if (!byLead.isEmpty()) {
            LBRInteractionReparentService.reparent(byLead.values());
        }
    }

    public void finish(Database.BatchableContext bc) {}

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LBRInteractionConvertSweeper(), 200);
    }
}
