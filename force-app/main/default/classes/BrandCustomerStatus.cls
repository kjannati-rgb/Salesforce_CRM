/**
 * BrandCustomerStatus
 * -------------------
 * Brand/product-level "existing customer" assessment. A firm is a customer FOR A
 * GIVEN BRAND only if it holds an active subscription for that brand — so the same
 * firm can be a Lexology customer and a Law.com prospect at the same time.
 *
 * Active subscription = either an active CPQ SBQQ__Subscription__c, or a legacy ALM
 * Opportunity line whose term spans today — checked across the whole Firm hierarchy
 * (the Firm + every Office whose Ultimate_Account__c is the Firm).
 */
public with sharing class BrandCustomerStatus {

    public class Status {
        @AuraEnabled public Boolean isCustomer;
        @AuraEnabled public String brand;     // canonical Product2.Brand__c evaluated
        @AuraEnabled public String label;     // customer | prospect | unknown
        @AuraEnabled public String evidence;
        @AuraEnabled public Integer activeSubs;
        @AuraEnabled public Date renewalDate; // earliest end-date of an active term for this brand (drives renewal framing)
        @AuraEnabled public Boolean familyCustomer; // active sub for a SIBLING brand in the same family (cross-sell within e.g. Specialist Platforms)
        @AuraEnabled public String family;          // brand-family name this brand belongs to (e.g. Specialist Platforms)
    }

    // canonical brand -> family name, from Brand_Mapping__mdt.Family__c (cached per transaction)
    private static Map<String, String> familyByBrand;
    private static Map<String, String> familyMap() {
        if (familyByBrand == null) {
            familyByBrand = new Map<String, String>();
            for (Brand_Mapping__mdt m : Brand_Mapping__mdt.getAll().values()) {
                if (String.isNotBlank(m.Canonical_Brand__c) && String.isNotBlank(m.Family__c)) {
                    familyByBrand.put(m.Canonical_Brand__c, m.Family__c);
                }
            }
        }
        return familyByBrand;
    }
    /** The family a canonical brand belongs to (null if it isn't grouped). */
    public static String familyOf(String canonical) {
        return String.isBlank(canonical) ? null : familyMap().get(canonical);
    }
    /** Every canonical brand sharing a family (incl. the brand itself). */
    private static Set<String> siblingsOf(String canonical) {
        Set<String> out = new Set<String>();
        String fam = familyOf(canonical);
        if (fam == null) return out;
        for (String brand : familyMap().keySet()) {
            if (familyMap().get(brand) == fam) out.add(brand);
        }
        return out;
    }

    // canonical brand -> Product_Group__c to match on (when the line shares a Brand with siblings, e.g. Lexology PRO)
    private static Map<String, String> matchGroupByBrand;
    private static Map<String, String> matchGroupMap() {
        if (matchGroupByBrand == null) {
            matchGroupByBrand = new Map<String, String>();
            for (Brand_Mapping__mdt m : Brand_Mapping__mdt.getAll().values()) {
                if (String.isNotBlank(m.Canonical_Brand__c) && String.isNotBlank(m.Match_Product_Group__c)) {
                    matchGroupByBrand.put(m.Canonical_Brand__c, m.Match_Product_Group__c);
                }
            }
        }
        return matchGroupByBrand;
    }
    /** The Product_Group__c a canonical should match on instead of Brand__c (null = match by Brand). */
    public static String matchGroupFor(String canonical) {
        return String.isBlank(canonical) ? null : matchGroupMap().get(canonical);
    }

    /** Resolve an inbound brand/product value (Lead field or form) to a canonical Brand__c via CMDT. */
    public static String canonicalBrand(String sourceValue) {
        if (String.isBlank(sourceValue)) return null;
        String needle = sourceValue.trim();
        for (Brand_Mapping__mdt m : Brand_Mapping__mdt.getAll().values()) {
            if (m.Source_Value__c != null && m.Source_Value__c.equalsIgnoreCase(needle)) {
                return m.Canonical_Brand__c;
            }
        }
        return null;
    }

    /** Pick the first non-blank inbound brand signal, then resolve it to a canonical brand. */
    public static String resolveLeadBrand(String lexologyProduct, String almInterest, String formBrand) {
        for (String raw : new List<String>{ formBrand, lexologyProduct, almInterest }) {
            String c = canonicalBrand(raw);
            if (c != null) return c;
        }
        return null;
    }

    public static Status forFirm(Id firmId, String canonical) {
        Status s = new Status();
        s.brand = canonical;
        s.activeSubs = 0;
        s.familyCustomer = false;
        s.family = familyOf(canonical);
        if (firmId == null || String.isBlank(canonical)) {
            s.isCustomer = false;
            s.label = 'unknown';
            s.evidence = 'No brand resolved for this lead — brand-level customer status not assessed.';
            return s;
        }
        Set<Id> acctIds = new Set<Id>{ firmId };
        for (Account a : [SELECT Id FROM Account WHERE Ultimate_Account__c = :firmId]) acctIds.add(a.Id);

        Date today = Date.today();
        // Some product lines share a Brand and are only separable by Product_Group__c (e.g. Lexology PRO
        // vs Lexology Intelligence). Match on the group when the mapping specifies one, else on Brand.
        String matchGroup = matchGroupFor(canonical);
        String cpqPredicate = (matchGroup != null)
            ? 'SBQQ__Product__r.Product_Group__c = :matchGroup' : 'SBQQ__Product__r.Brand__c = :canonical';
        String almPredicate = (matchGroup != null)
            ? 'Product2.Product_Group__c = :matchGroup' : 'Product2.Brand__c = :canonical';
        // Count active terms AND grab the earliest end-date in one aggregate per source, so we can
        // tell an upsell (term running) from a renewal (term ending soon).
        Integer cpq = 0; Date cpqEnd = null;
        for (AggregateResult ar : Database.query(
            'SELECT COUNT(Id) c, MIN(SBQQ__EndDate__c) e FROM SBQQ__Subscription__c'
            + ' WHERE SBQQ__Account__c IN :acctIds AND ' + cpqPredicate
            + ' AND SBQQ__StartDate__c <= :today AND SBQQ__EndDate__c >= :today AND SBQQ__TerminatedDate__c = null'
        )) { cpq = (Integer) ar.get('c'); cpqEnd = (Date) ar.get('e'); }
        Integer alm = 0; Date almEnd = null;
        for (AggregateResult ar : Database.query(
            'SELECT COUNT(Id) c, MIN(Opportunity.Opportunity_End_Date__c) e FROM OpportunityLineItem'
            + ' WHERE Opportunity.AccountId IN :acctIds AND ' + almPredicate
            + ' AND Opportunity.Opportunity_Start_Date__c <= :today AND Opportunity.Opportunity_End_Date__c >= :today'
        )) { alm = (Integer) ar.get('c'); almEnd = (Date) ar.get('e'); }
        s.activeSubs = cpq + alm;
        s.isCustomer = s.activeSubs > 0;
        // earliest active term end across both sources = the next renewal moment
        if (cpqEnd != null && (almEnd == null || cpqEnd <= almEnd)) s.renewalDate = cpqEnd;
        else if (almEnd != null) s.renewalDate = almEnd;
        s.label = s.isCustomer ? 'customer' : 'prospect';

        // Family cross-sell: if they don't hold THIS title but hold a sibling in the same family
        // (e.g. another Specialist Platform), they're a warm cross-sell, not net-new.
        if (s.isCustomer) {
            s.familyCustomer = true;   // holding the title implies family membership
        } else if (String.isNotBlank(s.family)) {
            Set<String> siblings = siblingsOf(canonical);
            siblings.remove(canonical);
            if (!siblings.isEmpty()) {
                Integer fcpq = [
                    SELECT COUNT() FROM SBQQ__Subscription__c
                    WHERE SBQQ__Account__c IN :acctIds AND SBQQ__Product__r.Brand__c IN :siblings
                      AND SBQQ__StartDate__c <= :today AND SBQQ__EndDate__c >= :today
                      AND SBQQ__TerminatedDate__c = null
                ];
                Integer falm = 0;
                if (fcpq == 0) {
                    falm = [
                        SELECT COUNT() FROM OpportunityLineItem
                        WHERE Opportunity.AccountId IN :acctIds AND Product2.Brand__c IN :siblings
                          AND Opportunity.Opportunity_Start_Date__c <= :today
                          AND Opportunity.Opportunity_End_Date__c >= :today
                    ];
                }
                s.familyCustomer = (fcpq + falm) > 0;
            }
        }

        s.evidence = s.isCustomer
            ? 'Active ' + canonical + ' subscription under this Firm (' + cpq + ' CPQ · ' + alm + ' legacy ALM) → existing customer / upsell.'
            : (s.familyCustomer
                ? 'No active ' + canonical + ' subscription, but the firm holds another ' + s.family
                    + ' title → cross-sell within ' + s.family + '.'
                : 'No active ' + canonical + ' subscription under this Firm → net-new for ' + canonical
                    + ' (the firm may still be a customer of other brands).');
        return s;
    }
}
