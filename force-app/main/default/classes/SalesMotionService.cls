/**
 * SalesMotionService
 * ------------------
 * Door-agnostic source of truth for the sales motion of an inbound enquiry:
 * New Business | Cross-sell | Upsell | Renewal.
 *
 * Used by BOTH conversion doors so the classification can never drift:
 *  - Door 1 (SDR cockpit / SmartConvertController) — at match preview AND at convert.
 *  - Door 2 (Pardot form completion) — via the @InvocableMethod, for flow.
 *
 * Motion rules (per-title customer, with family cross-sell):
 *  - active term for THIS brand, ending within the renewal window  -> Renewal
 *  - active term for THIS brand, ending later                      -> Upsell
 *  - active term for a SIBLING brand in the same family, OR any
 *    prior won business with the firm                              -> Cross-sell
 *  - otherwise                                                     -> New Business
 */
public with sharing class SalesMotionService {

    @TestVisible private static final Integer RENEWAL_WINDOW_DAYS = 90;

    public class Assessment {
        @AuraEnabled public String brand;          // canonical brand (display)
        @AuraEnabled public String brandStatus;    // customer | prospect | unknown
        @AuraEnabled public Boolean brandCustomer; // active term for this exact title
        @AuraEnabled public Boolean familyCustomer;// active term for a sibling in the same family
        @AuraEnabled public String brandFamily;    // family name (e.g. Specialist Platforms)
        @AuraEnabled public Boolean knownAccount;  // firm has prior won business (any brand)
        @AuraEnabled public String motion;         // New Business | Cross-sell | Upsell | Renewal
        @AuraEnabled public Date renewalDate;      // active term end (Upsell/Renewal)
    }

    /** Assess from an already-resolved canonical brand + the firm. */
    public static Assessment assess(Id firmId, String canonicalBrand) {
        Assessment a = new Assessment();
        a.brand = canonicalBrand;
        a.brandFamily = BrandCustomerStatus.familyOf(canonicalBrand);
        a.brandCustomer = false;
        a.familyCustomer = false;
        if (firmId != null && String.isNotBlank(canonicalBrand)) {
            BrandCustomerStatus.Status bs = BrandCustomerStatus.forFirm(firmId, canonicalBrand);
            a.brandStatus = bs.label;
            a.brandCustomer = bs.isCustomer == true;
            a.familyCustomer = bs.familyCustomer == true;
            a.renewalDate = bs.renewalDate;
        } else {
            a.brandStatus = 'unknown';
        }
        a.knownAccount = firmHasWonBusiness(firmId);
        a.motion = classify(canonicalBrand, a.brandCustomer, a.familyCustomer, a.renewalDate, a.knownAccount);
        return a;
    }

    /** Assess straight from raw inbound brand signals (Lead fields or a Pardot form value). */
    public static Assessment assessFromSource(Id firmId, String lexologyProduct, String almInterest, String formBrand) {
        String canonical = BrandCustomerStatus.resolveLeadBrand(lexologyProduct, almInterest, formBrand);
        return assess(firmId, canonical);
    }

    /** Pure rule: decide the motion from the resolved signals. */
    public static String classify(String brand, Boolean brandCustomer, Boolean familyCustomer,
            Date renewalDate, Boolean knownAccount) {
        if (String.isNotBlank(brand) && brandCustomer == true) {
            Boolean renewing = renewalDate != null && renewalDate <= Date.today().addDays(RENEWAL_WINDOW_DAYS);
            return renewing ? 'Renewal' : 'Upsell';
        }
        if (familyCustomer == true || knownAccount == true) return 'Cross-sell';
        return 'New Business';
    }

    /** True if the firm (or any office under it) has at least one won opportunity. */
    public static Boolean firmHasWonBusiness(Id firmId) {
        if (firmId == null) return false;
        for (AggregateResult ar : [
            SELECT SUM(No_of_Won_Office_Opportunities__c) s FROM Account
            WHERE Id = :firmId OR Ultimate_Account__c = :firmId
        ]) {
            Decimal won = (Decimal) ar.get('s');
            return won != null && won > 0;
        }
        return false;
    }

    // ===== Door 2 (Pardot / flow) entry point =====

    public class Request {
        @InvocableVariable(required=true) public Id firmId;       // resolved Firm (or Office; we walk up)
        @InvocableVariable public String formBrand;               // Pardot_Form_Completion__c.Brand__c
        @InvocableVariable public String lexologyProduct;
        @InvocableVariable public String almInterest;
    }
    public class Response {
        @InvocableVariable public String brand;
        @InvocableVariable public String brandStatus;
        @InvocableVariable public String brandFamily;
        @InvocableVariable public String motion;
        @InvocableVariable public Boolean familyCustomer;
        @InvocableVariable public Boolean knownAccount;
        @InvocableVariable public Date renewalDate;
    }

    /**
     * NOTE — single-record oriented. assess() runs several per-firm aggregate queries, so this
     * loops SOQL per request. Safe for a record-triggered flow firing per Pardot form completion;
     * NOT safe for a 200-record batch. Before wiring high-volume bulk, bulkify by accepting a
     * Set<firmId> in BrandCustomerStatus.forFirm and resolving statuses in one pass. (Pardot Phase 1.)
     */
    @InvocableMethod(label='Assess Sales Motion' category='Smart Convert'
        description='Classify the sales motion (New Business/Cross-sell/Upsell/Renewal) for a firm + inbound brand. Single-record oriented.')
    public static List<Response> assessInvocable(List<Request> reqs) {
        List<Response> out = new List<Response>();
        for (Request r : reqs) {
            Id firmId = firmFrom(r.firmId);
            Assessment a = assessFromSource(firmId, r.lexologyProduct, r.almInterest, r.formBrand);
            Response resp = new Response();
            resp.brand = a.brand;
            resp.brandStatus = a.brandStatus;
            resp.brandFamily = a.brandFamily;
            resp.motion = a.motion;
            resp.familyCustomer = a.familyCustomer;
            resp.knownAccount = a.knownAccount;
            resp.renewalDate = a.renewalDate;
            out.add(resp);
        }
        return out;
    }

    /** Accept either a Firm or an Office id and return the Firm. */
    private static Id firmFrom(Id acctId) {
        if (acctId == null) return null;
        for (Account o : [SELECT Ultimate_Account__c FROM Account WHERE Id = :acctId LIMIT 1]) {
            return (o.Ultimate_Account__c != null) ? o.Ultimate_Account__c : acctId;
        }
        return acctId;
    }
}
