/**
 * PFC Triage Cockpit — Phase D. Data provider for the pfcQualityCard LWC.
 *
 * One wrapper, two render modes (decided client-side on Contact__c ≠ null):
 *  - Lead mode: fit score + reasoning, email domain classification (Freemail_Domain__mdt),
 *    duplicate detection (email OR Pardot prospect ID, last 90 days — display-only,
 *    deliberately wider than the PFC_On_Save auto-linker which stays lookup+brand based).
 *  - Contact mode: firm-level subscription rollup via Ultimate_Parent__c on
 *    SBQQ__Subscription__c (same "active" definition as FirmSalesSummaryController:
 *    started, not ended, not terminated, not bundled) + entitlement overlap flag via
 *    Brand_Family_Map__mdt.
 *
 * Sharing: class runs `with sharing`. The subscription rollup alone runs `without sharing`
 * (inner class) because sales-rep profiles have no sharing access to CPQ subscription
 * records; the card exposes only aggregate counts per product family, never record detail.
 * Precedent: Account Team Manager LWC controller.
 */
public with sharing class PFCQualityCardController {

    @AuraEnabled(cacheable=true)
    public static CardData getCardData(Id recordId) {
        List<Pardot_Form_Completion__c> pfcs = [
            SELECT Id, Fit_Score__c, Score_Reasoning__c, Clay_Routed__c, PFC_Source__c,
                   Email__c, Prospect_ID__c, Product_Brand__c, Contact__c, Lead__c,
                   Account_Contact__c, Account_Contact__r.Name,
                   Account_Contact__r.Ultimate_Account__c,
                   Account_Contact__r.Ultimate_Account__r.Name,
                   Contact__r.AccountId, Contact__r.Account.Name,
                   Contact__r.Account.Ultimate_Account__c,
                   Contact__r.Account.Ultimate_Account__r.Name
            FROM Pardot_Form_Completion__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (pfcs.isEmpty()) {
            return null;
        }
        Pardot_Form_Completion__c pfc = pfcs[0];

        CardData data = new CardData();
        data.mode = pfc.Contact__c != null ? 'contact' : 'lead';
        data.fitScore = pfc.Fit_Score__c == null ? null : Integer.valueOf(pfc.Fit_Score__c);
        data.scoreReasoning = pfc.Score_Reasoning__c;
        data.clayRouted = pfc.Clay_Routed__c;
        data.pfcSource = pfc.PFC_Source__c;
        data.email = pfc.Email__c;
        data.domainName = registrableDomain(pfc.Email__c);
        data.domainClass = classifyDomain(data.domainName);
        data.duplicates = findDuplicates(pfc);
        // Account_Contact__c is stamped by PFC_On_Save, which deliberately skips records
        // created already-closed — fall back to the Contact's own account so contact mode
        // never runs without firm context when an account exists at all.
        if (data.mode == 'contact') {
            if (pfc.Account_Contact__c != null) {
                data.firm = buildFirmContext(pfc, pfc.Account_Contact__c,
                    pfc.Account_Contact__r.Name,
                    pfc.Account_Contact__r.Ultimate_Account__c,
                    pfc.Account_Contact__r.Ultimate_Account__r?.Name);
            } else if (pfc.Contact__r.AccountId != null) {
                data.firm = buildFirmContext(pfc, pfc.Contact__r.AccountId,
                    pfc.Contact__r.Account.Name,
                    pfc.Contact__r.Account.Ultimate_Account__c,
                    pfc.Contact__r.Account.Ultimate_Account__r?.Name);
            }
        }
        return data;
    }

    @TestVisible
    private static String registrableDomain(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return null;
        }
        return email.substringAfterLast('@').trim().toLowerCase();
    }

    private static String classifyDomain(String domain) {
        if (String.isBlank(domain)) {
            return 'none';
        }
        for (Freemail_Domain__mdt row : Freemail_Domain__mdt.getAll().values()) {
            if (row.Domain__c != null && row.Domain__c.toLowerCase() == domain) {
                return 'freemail';
            }
        }
        return 'corporate';
    }

    /**
     * Email__c / Prospect_ID__c are cross-object formulas (not filterable in SOQL), so
     * matching resolves through the underlying person records instead: any Lead or Contact
     * with the same email, plus the record's own Lead/Contact lookups. This also catches
     * the same person existing as both a Lead and a Contact.
     */
    private static List<DupeInfo> findDuplicates(Pardot_Form_Completion__c pfc) {
        List<DupeInfo> dupes = new List<DupeInfo>();
        Set<Id> leadIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        if (pfc.Lead__c != null) {
            leadIds.add(pfc.Lead__c);
        }
        if (pfc.Contact__c != null) {
            contactIds.add(pfc.Contact__c);
        }
        if (String.isNotBlank(pfc.Email__c)) {
            String em = pfc.Email__c;
            for (Lead l : [SELECT Id FROM Lead WHERE Email = :em LIMIT 50]) {
                leadIds.add(l.Id);
            }
            for (Contact c : [SELECT Id FROM Contact WHERE Email = :em LIMIT 50]) {
                contactIds.add(c.Id);
            }
        }
        if (leadIds.isEmpty() && contactIds.isEmpty()) {
            return dupes;
        }
        Id selfId = pfc.Id;
        List<Pardot_Form_Completion__c> rows = [
            SELECT Id, Name, Form_Name__c, Sales_Stage__c, CreatedDate
            FROM Pardot_Form_Completion__c
            WHERE Id != :selfId AND CreatedDate = LAST_N_DAYS:90
              AND (Lead__c IN :leadIds OR Contact__c IN :contactIds)
            ORDER BY CreatedDate DESC LIMIT 10
        ];
        for (Pardot_Form_Completion__c row : rows) {
            DupeInfo d = new DupeInfo();
            d.recordId = row.Id;
            d.name = row.Name;
            d.formName = row.Form_Name__c;
            d.stage = row.Sales_Stage__c;
            d.createdDate = row.CreatedDate;
            dupes.add(d);
        }
        return dupes;
    }

    private static FirmContext buildFirmContext(Pardot_Form_Completion__c pfc,
            Id officeId, String officeName, Id ultimateId, String ultimateName) {
        FirmContext firm = new FirmContext();
        Id firmId = ultimateId != null ? ultimateId : officeId;
        firm.firmId = firmId;
        firm.firmName = ultimateId != null ? ultimateName : officeName;
        firm.officeName = officeName;

        firm.families = new List<FamilyCount>();
        firm.activeSubs = 0;
        Map<String, Integer> byFamily = new Map<String, Integer>();
        for (AggregateResult ar : new SubscriptionRollup().countByFamily(firmId)) {
            String fam = (String) ar.get('fam');
            Integer cnt = (Integer) ar.get('c');
            FamilyCount fc = new FamilyCount();
            fc.family = fam == null ? 'Uncategorised' : fam;
            fc.count = cnt;
            firm.families.add(fc);
            firm.activeSubs += cnt;
            if (fam != null) {
                byFamily.put(fam.toLowerCase(), cnt);
            }
        }
        firm.familyCount = firm.families.size();
        firm.existingCustomer = firm.activeSubs > 0;

        firm.requestedBrand = pfc.Product_Brand__c;
        firm.requestedFamily = mapBrandToFamily(pfc.Product_Brand__c);
        firm.requestedBrandFamilyOverlap = firm.requestedFamily != null
            && byFamily.containsKey(firm.requestedFamily.toLowerCase());
        return firm;
    }

    private static String mapBrandToFamily(String brand) {
        if (String.isBlank(brand)) {
            return null;
        }
        for (Brand_Family_Map__mdt row : Brand_Family_Map__mdt.getAll().values()) {
            if (row.Brand__c != null && row.Brand__c.equalsIgnoreCase(brand)) {
                return row.Product_Family__c;
            }
        }
        return null;
    }

    /** Aggregate-only escalation: reps have no sharing access to CPQ subscriptions. */
    private without sharing class SubscriptionRollup {
        List<AggregateResult> countByFamily(Id firmId) {
            Date today = Date.today();
            return [
                SELECT SBQQ__Product__r.Family fam, COUNT(Id) c
                FROM SBQQ__Subscription__c
                WHERE Ultimate_Parent__c = :firmId
                  AND SBQQ__StartDate__c <= :today
                  AND SBQQ__EndDate__c >= :today
                  AND SBQQ__TerminatedDate__c = null
                  AND SBQQ__Bundled__c = false
                GROUP BY SBQQ__Product__r.Family
                ORDER BY COUNT(Id) DESC
            ];
        }
    }

    public class CardData {
        @AuraEnabled public String mode;
        @AuraEnabled public Integer fitScore;
        @AuraEnabled public String scoreReasoning;
        @AuraEnabled public Boolean clayRouted;
        @AuraEnabled public String pfcSource;
        @AuraEnabled public String email;
        @AuraEnabled public String domainName;
        @AuraEnabled public String domainClass;
        @AuraEnabled public List<DupeInfo> duplicates;
        @AuraEnabled public FirmContext firm;
    }

    public class DupeInfo {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String formName;
        @AuraEnabled public String stage;
        @AuraEnabled public Datetime createdDate;
    }

    public class FamilyCount {
        @AuraEnabled public String family;
        @AuraEnabled public Integer count;
    }

    public class FirmContext {
        @AuraEnabled public Id firmId;
        @AuraEnabled public String firmName;
        @AuraEnabled public String officeName;
        @AuraEnabled public Integer activeSubs;
        @AuraEnabled public Integer familyCount;
        @AuraEnabled public List<FamilyCount> families;
        @AuraEnabled public Boolean existingCustomer;
        @AuraEnabled public String requestedBrand;
        @AuraEnabled public String requestedFamily;
        @AuraEnabled public Boolean requestedBrandFamilyOverlap;
    }
}
