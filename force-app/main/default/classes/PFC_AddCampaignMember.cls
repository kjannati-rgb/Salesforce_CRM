/**
 * Adds a Contact or Lead to a Campaign, de-duplicating so a duplicate
 * CampaignMember never surfaces as a DML fault (and therefore never triggers
 * a flow error email).
 *
 * Why this exists: PFC_On_Save is an after-save record-triggered flow. When
 * several Pardot_Form_Completion__c records for the same person + campaign are
 * saved in one transaction, Salesforce bulkifies the CampaignMember insert into
 * a single DML containing identical rows. A flow "Create Records" element can't
 * see its sibling interviews' in-flight rows, so the CampaignMember unique
 * constraint rejects the duplicates with DUPLICATE_VALUE. The fault is caught
 * and logged, but the platform still emails the interview error.
 *
 * When the flow calls this invocable instead, Salesforce bulkifies the sibling
 * interviews into a single addMembers() call, so the duplicates are collapsed
 * in-memory before any DML. Three further layers make it race-proof:
 *   1. In-call de-dup by (campaignId:memberId) key.
 *   2. A transaction-scoped static Set, in case interviews arrive across more
 *      than one invocation in the same transaction.
 *   3. Partial-success insert (allOrNone = false) so any residual duplicate is
 *      returned on the SaveResult instead of thrown.
 */
public with sharing class PFC_AddCampaignMember {

    // Persists across sibling flow interviews within the same transaction.
    @TestVisible
    private static Set<String> processedKeys = new Set<String>();

    public class Request {
        @InvocableVariable(label='Campaign Id' required=true)
        public Id campaignId;

        @InvocableVariable(label='Contact Id')
        public Id contactId;

        @InvocableVariable(label='Lead Id')
        public Id leadId;

        @InvocableVariable(label='Member Status')
        public String status;
    }

    @InvocableMethod(
        label='Add Campaign Member (dedup)'
        description='Adds a Contact or Lead to a Campaign, de-duplicating within the transaction and against committed members so a duplicate never surfaces as a DML fault.'
    )
    public static void addMembers(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        // 1) Collapse duplicates within this invocation, skipping keys already
        //    staged earlier in the same transaction (sibling interviews).
        Map<String, CampaignMember> byKey = new Map<String, CampaignMember>();
        Set<Id> campaignIds = new Set<Id>();
        Set<Id> memberIds = new Set<Id>();

        for (Request r : requests) {
            Id memberId = (r.contactId != null) ? r.contactId : r.leadId;
            if (r.campaignId == null || memberId == null) {
                continue; // nothing to add
            }
            String key = r.campaignId + ':' + memberId;
            if (processedKeys.contains(key) || byKey.containsKey(key)) {
                continue;
            }
            CampaignMember cm = new CampaignMember(
                CampaignId = r.campaignId,
                Status = String.isBlank(r.status) ? 'Registered' : r.status
            );
            if (r.contactId != null) {
                cm.ContactId = r.contactId;
            } else {
                cm.LeadId = r.leadId;
            }
            byKey.put(key, cm);
            campaignIds.add(r.campaignId);
            memberIds.add(memberId);
        }

        if (byKey.isEmpty()) {
            return;
        }

        // Remember every key we considered, so later invocations in this
        // transaction short-circuit before touching the database.
        processedKeys.addAll(byKey.keySet());

        // 2) Drop any that already exist as committed members.
        for (CampaignMember existing : [
            SELECT CampaignId, ContactId, LeadId
            FROM CampaignMember
            WHERE CampaignId IN :campaignIds
              AND (ContactId IN :memberIds OR LeadId IN :memberIds)
        ]) {
            Id existingMember = (existing.ContactId != null) ? existing.ContactId : existing.LeadId;
            byKey.remove(existing.CampaignId + ':' + existingMember);
        }

        if (byKey.isEmpty()) {
            return;
        }

        // 3) Partial-success insert: a residual duplicate is returned on the
        //    SaveResult rather than thrown, so it never becomes a flow fault.
        Database.insert(byKey.values(), false);
    }
}
