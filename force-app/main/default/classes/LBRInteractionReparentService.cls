/**
 * LBRInteractionReparentService
 * -----------------------------
 * Re-parents lead-side LBR_Interactions__c onto the Contact/Account produced by a
 * Lead conversion (REV-68). Reusable by both the guided convert path
 * (LeadConvertInvocable) and the safety-net batch (LBRInteractionConvertSweeper).
 *
 * For each lead-side interaction:
 *   - If the target Contact already has a matching interaction (same Interaction_Code__c
 *     when populated, otherwise same Interaction_Type__c + Product__c + Interaction_Date__c),
 *     the lead-side duplicate is DELETED.
 *   - Otherwise it is re-parented: Contact__c = converted Contact, Account__c = converted
 *     Account, Ultimate_Account__c = that Account's Ultimate_Account__c (the org convention,
 *     mirrored from UltimateAccountBeforeSaving), and Lead__c is cleared in the SAME DML so
 *     neither Contact_or_Lead_Required nor Block_Converted_Lead fires.
 *   - When the conversion created an Opportunity, a Contact2Interaction__c row
 *     (Contact, Interaction, Opportunity) is inserted for each surviving interaction,
 *     skipping pairs that already exist.
 *
 * Bulk-safe: single queries / DML outside loops; handles 200 simultaneous conversions.
 */
public with sharing class LBRInteractionReparentService {

    /** Outcome of one Lead conversion. */
    public class ConvertedLead {
        public Id leadId;
        public Id contactId;
        public Id accountId;
        public Id opportunityId;
        public ConvertedLead(Id leadId, Id contactId, Id accountId, Id opportunityId) {
            this.leadId = leadId;
            this.contactId = contactId;
            this.accountId = accountId;
            this.opportunityId = opportunityId;
        }
    }

    public static void reparent(List<ConvertedLead> converts) {
        if (converts == null || converts.isEmpty()) return;

        Map<Id, ConvertedLead> byLead = new Map<Id, ConvertedLead>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> targetContactIds = new Set<Id>();
        for (ConvertedLead c : converts) {
            if (c == null || c.leadId == null || c.contactId == null) continue;
            byLead.put(c.leadId, c);
            targetContactIds.add(c.contactId);
            if (c.accountId != null) accountIds.add(c.accountId);
        }
        if (byLead.isEmpty()) return;

        // Lead-side interactions to process.
        List<LBR_Interactions__c> leadInteractions = [
            SELECT Id, Lead__c, Contact__c, Account__c, Ultimate_Account__c, Opportunity__c,
                   Interaction_Code__c, Interaction_Type__c, Product__c, Interaction_Date__c
            FROM LBR_Interactions__c
            WHERE Lead__c IN :byLead.keySet()
        ];
        if (leadInteractions.isEmpty()) return;

        // Ultimate account convention: interaction.Ultimate_Account__c = parentAccount.Ultimate_Account__c.
        Map<Id, Id> acctToUltimate = new Map<Id, Id>();
        for (Account a : [SELECT Id, Ultimate_Account__c FROM Account WHERE Id IN :accountIds]) {
            acctToUltimate.put(a.Id, a.Ultimate_Account__c);
        }

        // Existing Contact-side interactions, for dedup against the target Contact.
        Set<String> seenCodeKeys = new Set<String>();
        Set<String> seenCompositeKeys = new Set<String>();
        for (LBR_Interactions__c e : [
            SELECT Id, Contact__c, Interaction_Code__c, Interaction_Type__c, Product__c, Interaction_Date__c
            FROM LBR_Interactions__c
            WHERE Contact__c IN :targetContactIds
        ]) {
            if (String.isNotBlank(e.Interaction_Code__c)) {
                seenCodeKeys.add(codeKey(e.Contact__c, e.Interaction_Code__c));
            }
            seenCompositeKeys.add(compositeKey(e.Contact__c, e.Interaction_Type__c, e.Product__c, e.Interaction_Date__c));
        }

        List<LBR_Interactions__c> toUpdate = new List<LBR_Interactions__c>();
        List<LBR_Interactions__c> toDelete = new List<LBR_Interactions__c>();
        // Surviving interaction -> (contact, opportunity) for Contact2Interaction__c.
        Map<Id, ConvertedLead> survivorContext = new Map<Id, ConvertedLead>();

        for (LBR_Interactions__c li : leadInteractions) {
            ConvertedLead c = byLead.get(li.Lead__c);
            if (c == null) continue;

            Boolean hasCode = String.isNotBlank(li.Interaction_Code__c);
            String ck = hasCode ? codeKey(c.contactId, li.Interaction_Code__c) : null;
            String comp = compositeKey(c.contactId, li.Interaction_Type__c, li.Product__c, li.Interaction_Date__c);

            Boolean dup = hasCode ? seenCodeKeys.contains(ck) : seenCompositeKeys.contains(comp);
            if (dup) {
                toDelete.add(new LBR_Interactions__c(Id = li.Id));
                continue;
            }

            // Record this one so siblings re-parented in the same run dedupe against it too.
            if (hasCode) seenCodeKeys.add(ck);
            seenCompositeKeys.add(comp);

            li.Contact__c = c.contactId;
            li.Account__c = c.accountId;
            li.Ultimate_Account__c = (c.accountId != null) ? acctToUltimate.get(c.accountId) : null;
            li.Lead__c = null;
            toUpdate.add(li);

            if (c.opportunityId != null) survivorContext.put(li.Id, c);
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toDelete.isEmpty()) delete toDelete;

        insertContact2Interactions(survivorContext);
    }

    private static void insertContact2Interactions(Map<Id, ConvertedLead> survivorContext) {
        if (survivorContext.isEmpty()) return;

        // Skip (interaction, opportunity) pairs that already exist.
        Set<String> existingPairs = new Set<String>();
        for (Contact2Interaction__c x : [
            SELECT LBR_Interactions__c, Opportunity__c
            FROM Contact2Interaction__c
            WHERE LBR_Interactions__c IN :survivorContext.keySet()
        ]) {
            existingPairs.add(pairKey(x.LBR_Interactions__c, x.Opportunity__c));
        }

        List<Contact2Interaction__c> toInsert = new List<Contact2Interaction__c>();
        for (Id interactionId : survivorContext.keySet()) {
            ConvertedLead c = survivorContext.get(interactionId);
            if (existingPairs.contains(pairKey(interactionId, c.opportunityId))) continue;
            toInsert.add(new Contact2Interaction__c(
                Contact__c = c.contactId,
                LBR_Interactions__c = interactionId,
                Opportunity__c = c.opportunityId
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static String codeKey(Id contactId, String code) {
        return String.valueOf(contactId) + '|' + code.toLowerCase();
    }

    private static String compositeKey(Id contactId, String type, String product, Date d) {
        return String.valueOf(contactId) + '|'
            + (type == null ? '' : type) + '|'
            + (product == null ? '' : product) + '|'
            + (d == null ? '' : String.valueOf(d));
    }

    private static String pairKey(Id interactionId, Id opportunityId) {
        return String.valueOf(interactionId) + '|' + String.valueOf(opportunityId);
    }
}
