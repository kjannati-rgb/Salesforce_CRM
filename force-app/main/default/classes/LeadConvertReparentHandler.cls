/**
 * LeadConvertReparentHandler
 * --------------------------
 * Re-parents LBR interactions the moment a Lead is converted via ANY path (standard Convert
 * button, Apex, import) — REV-68 follow-up so interactions land on the Contact immediately
 * instead of waiting for the nightly LBRInteractionConvertSweeper.
 *
 * Runs inside the conversion transaction, so a re-parent problem must NOT roll back the
 * user's lead conversion: the reparent call is guarded, and the sweeper retries anything missed.
 */
public with sharing class LeadConvertReparentHandler {

    public static void handle(List<Lead> newList, Map<Id, Lead> oldMap) {
        List<LBRInteractionReparentService.ConvertedLead> converts =
            new List<LBRInteractionReparentService.ConvertedLead>();
        for (Lead l : newList) {
            Lead prior = (oldMap != null) ? oldMap.get(l.Id) : null;
            Boolean wasConverted = (prior != null && prior.IsConverted == true);
            if (l.IsConverted == true && !wasConverted && l.ConvertedContactId != null) {
                converts.add(new LBRInteractionReparentService.ConvertedLead(
                    l.Id, l.ConvertedContactId, l.ConvertedAccountId, l.ConvertedOpportunityId));
            }
        }
        if (converts.isEmpty()) return;

        try {
            LBRInteractionReparentService.reparent(converts);
        } catch (Exception e) {
            // Never fail the lead conversion over a re-parent issue; the nightly
            // LBRInteractionConvertSweeper will pick up anything left on a converted Lead.
            System.debug(LoggingLevel.ERROR, 'LeadConvertReparent skipped (sweeper will retry): ' + e.getMessage());
        }
    }
}
