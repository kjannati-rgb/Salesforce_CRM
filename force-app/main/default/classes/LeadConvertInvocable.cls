/**
 * LeadConvertInvocable
 * --------------------
 * Door-1 convert step for World-Class Lead Conversion. Converts a Lead into a
 * SPECIFIED existing Office Account (and optionally an existing Contact), via the
 * platform convert. Kept as a thin invocable so the Screen Flow stays declarative.
 *
 * The matcher (LeadMatchSelectService) decides the target; this only executes the
 * convert the SDR confirmed. Partial-success mode so a managed-package rejection
 * (AddressTools / DupeBlocker) surfaces as a message rather than an unhandled error.
 */
public with sharing class LeadConvertInvocable {

    public class Request {
        @InvocableVariable(required=true label='Lead Id') public Id leadId;
        @InvocableVariable(label='Office Account Id (convert into)') public Id accountId;
        @InvocableVariable(label='Existing Contact Id (optional)') public Id contactId;
        @InvocableVariable(label='Create Opportunity') public Boolean createOpportunity;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public Id accountId;
        @InvocableVariable public Id contactId;
        @InvocableVariable public Id opportunityId;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Convert Lead (Guided)'
                     description='Convert a Lead into a specified existing Office Account.')
    public static List<Result> convert(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        String convertedStatus = convertedStatusLabel();

        List<Database.LeadConvert> lcs = new List<Database.LeadConvert>();
        for (Request r : requests) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(r.leadId);
            lc.setConvertedStatus(convertedStatus);
            if (r.accountId != null) lc.setAccountId(r.accountId);
            if (r.contactId != null) lc.setContactId(r.contactId);
            lc.setDoNotCreateOpportunity(r.createOpportunity != true);
            lcs.add(lc);
        }

        List<Database.LeadConvertResult> lcrs = Database.convertLead(lcs, false);
        List<LBRInteractionReparentService.ConvertedLead> converts =
            new List<LBRInteractionReparentService.ConvertedLead>();
        for (Integer i = 0; i < lcrs.size(); i++) {
            Database.LeadConvertResult lcr = lcrs[i];
            Result res = new Result();
            res.success = lcr.isSuccess();
            if (lcr.isSuccess()) {
                res.accountId = lcr.getAccountId();
                res.contactId = lcr.getContactId();
                res.opportunityId = lcr.getOpportunityId();
                res.message = 'Converted successfully.';
                // REV-68: collect for re-homing lead-side interactions post-convert.
                converts.add(new LBRInteractionReparentService.ConvertedLead(
                    requests[i].leadId, lcr.getContactId(), lcr.getAccountId(), lcr.getOpportunityId()));
            } else {
                String msg = '';
                for (Database.Error e : lcr.getErrors()) msg += e.getMessage() + ' ';
                res.message = 'Convert blocked: ' + msg.trim();
            }
            results.add(res);
        }

        // REV-68: re-parent any LBR_Interactions__c that were sitting on the converted Lead.
        if (!converts.isEmpty()) {
            LBRInteractionReparentService.reparent(converts);
        }
        return results;
    }

    private static String convertedStatusLabel() {
        for (LeadStatus s : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true ORDER BY SortOrder NULLS LAST LIMIT 1]) {
            return s.MasterLabel;
        }
        return 'Closed - Converted';
    }
}
