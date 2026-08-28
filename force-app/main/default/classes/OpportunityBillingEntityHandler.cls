public class OpportunityBillingEntityHandler {

    private static final Set<String> TYPE_RENEWALS           = new Set<String>{'Renewal', 'Auto-Renewal'};
    private static final Set<String> TYPE_REPEAT_BUSINESS    = new Set<String>{'Repeat Business', 'Auto-Repeat Business'};

    private static final String COUNTRY_USA = 'United States';
    private static final String COUNTRY_HK  = 'Hong Kong';

    private static final String BILLING_USA = 'LLC';
    private static final String BILLING_HK  = 'GHK';

    // Per-transaction memo. CPQ and the flow chain re-save the same Opportunity several
    // times per commit, and the blankWithLineItems condition keeps shouldRun true on every
    // save of an open opp with lines and no billing entity — without these caches the OLI
    // and previous-opportunity queries repeat on each save. Entries for an opp are evicted
    // when its line-item count changes (the roll-up summary system-fires the trigger),
    // so a changed line set is re-read.
    @TestVisible private static Map<Id, Set<String>> countryCache = new Map<Id, Set<String>>();
    @TestVisible private static Set<Id> countryCacheIds = new Set<Id>();
    @TestVisible private static Map<Id, Opportunity> prevOppCache = new Map<Id, Opportunity>();
    @TestVisible private static Set<Id> prevOppCacheIds = new Set<Id>();

    public static void evaluate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        Set<Id> oppIdsNeedingOLI   = new Set<Id>();
        Set<Id> oppIdsNeedingPrev  = new Set<Id>();

        for (Opportunity opp : newList) {
            String typeVal = (opp.Type == null) ? null : opp.Type.trim();
            Boolean shouldRun = true;
            if (Trigger.isUpdate) {
                Opportunity oldOpp = oldMap.get(opp.Id);
                Boolean countChanged = oldOpp.No_of_Line_Items__c != opp.No_of_Line_Items__c;
                Boolean typeChanged  = oldOpp.Type != opp.Type;
                Boolean preOppChanged  = (oldOpp.Previous_Opportunity__c == null)  && (oldOpp.Previous_Opportunity__c != opp.Previous_Opportunity__c);
                Boolean blankWithLineItems = String.isBlank(opp.Billing_Entity__c) && opp.No_of_Line_Items__c != null && opp.No_of_Line_Items__c > 0;
                shouldRun = countChanged || typeChanged || preOppChanged || blankWithLineItems;
                if (countChanged) {
                    countryCacheIds.remove(opp.Id); // line set changed — cached countries are stale
                }
            }

            if (!shouldRun) continue;

            if (typeVal != null && TYPE_RENEWALS.contains(typeVal) && opp.Previous_Opportunity__c != null) {
                oppIdsNeedingPrev.add(opp.Previous_Opportunity__c);
            }
            if (opp.Id != null) {
                oppIdsNeedingOLI.add(opp.Id);
            }
            if (typeVal != null && TYPE_REPEAT_BUSINESS.contains(typeVal) && opp.Previous_Opportunity__c != null) {
                oppIdsNeedingPrev.add(opp.Previous_Opportunity__c);
            }
        }

        Set<Id> prevToQuery = new Set<Id>();
        for (Id prevId : oppIdsNeedingPrev) {
            if (!prevOppCacheIds.contains(prevId)) prevToQuery.add(prevId);
        }
        if (!prevToQuery.isEmpty()) {
            for (Opportunity prev : [SELECT Id, Billing_Entity__c, IsClosed FROM Opportunity WHERE Id IN :prevToQuery]) {
                prevOppCache.put(prev.Id, prev);
            }
            prevOppCacheIds.addAll(prevToQuery);
        }

        Set<Id> oliToQuery = new Set<Id>();
        for (Id oppId : oppIdsNeedingOLI) {
            if (!countryCacheIds.contains(oppId)) oliToQuery.add(oppId);
        }
        if (!oliToQuery.isEmpty()) {
            for (Id oppId : oliToQuery) {
                countryCache.put(oppId, new Set<String>());
            }
            for (OpportunityLineItem oli : [SELECT OpportunityId, Product2.Event_Location_Country__c FROM OpportunityLineItem
                                            WHERE OpportunityId IN :oliToQuery]) {

                if (oli.OpportunityId == null) continue;

                String ctry = (oli.Product2 != null) ? oli.Product2.Event_Location_Country__c : null;

                if (String.isNotBlank(ctry)) {
                    countryCache.get(oli.OpportunityId).add(ctry.trim());
                }
            }
            countryCacheIds.addAll(oliToQuery);
        }

        // Custom setting read via the platform cache — zero SOQL (the previous SOQL read
        // counted one query per save).
        Map<String, String> fullToAbbrevMap = new Map<String, String>();
        for (Opportunity_Billing_Entity_Mapping__c cs : Opportunity_Billing_Entity_Mapping__c.getAll().values()) {
            if (String.isNotBlank(cs.Full_Billing_Entity_Name__c)) {
                fullToAbbrevMap.put(cs.Full_Billing_Entity_Name__c.trim(), cs.Abbreviation_Billing_Entity_Name__c);
            }
        }
        // Guard set: a previous opportunity's Billing_Entity__c is only copied forward when it
        // is one of the mapped abbreviations — foreign values (e.g. migrated source-org record
        // Ids) must not self-propagate onto new renewals.
        Set<String> validEntities = new Set<String>();
        for (String abbrev : fullToAbbrevMap.values()) {
            if (String.isNotBlank(abbrev)) {
                validEntities.add(abbrev.trim());
            }
        }
        for (Opportunity opp : newList) {

            Boolean shouldRun = true;
            if (Trigger.isUpdate) {
                Opportunity oldOpp = oldMap.get(opp.Id);
                Boolean countChanged = oldOpp.No_of_Line_Items__c != opp.No_of_Line_Items__c;
                Boolean typeChanged  = oldOpp.Type != opp.Type;
                Boolean preOppChanged  = (oldOpp.Previous_Opportunity__c == null)  && (oldOpp.Previous_Opportunity__c != opp.Previous_Opportunity__c);
                Boolean blankWithLineItems = String.isBlank(opp.Billing_Entity__c) && opp.No_of_Line_Items__c != null && opp.No_of_Line_Items__c > 0;
                shouldRun = countChanged || typeChanged || preOppChanged || blankWithLineItems;
            }
            if (Trigger.isInsert) shouldRun = true;

            if (!shouldRun) continue;

            String typeVal = (opp.Type == null) ? null : opp.Type.trim();

            if (typeVal != null && TYPE_RENEWALS.contains(typeVal)) {
                if (opp.Previous_Opportunity__c != null) {
                    Opportunity prevOpp = prevOppCache.get(opp.Previous_Opportunity__c);
                    if (prevOpp != null && String.isNotBlank(prevOpp.Billing_Entity__c) && validEntities.contains(prevOpp.Billing_Entity__c.trim())) {
                        opp.Billing_Entity__c = prevOpp.Billing_Entity__c;
                        continue;
                    }
                    if (prevOpp == null || !prevOpp.IsClosed) {
                        continue;
                    }
                    // previous opportunity is closed but has no copyable value - fall through to New Business logic below
                }
            } else if (typeVal != null && TYPE_REPEAT_BUSINESS.contains(typeVal)) {
                if (opp.Previous_Opportunity__c != null) {
                    Opportunity prevOpp = prevOppCache.get(opp.Previous_Opportunity__c);
                    if (prevOpp != null && String.isNotBlank(prevOpp.Billing_Entity__c) && validEntities.contains(prevOpp.Billing_Entity__c.trim())) {
                        opp.Billing_Entity__c = prevOpp.Billing_Entity__c;
                        continue;
                    }
                    if (prevOpp == null || !prevOpp.IsClosed) {
                        continue;
                    }
                    // previous opportunity is closed but has no copyable value - fall through to New Business logic below
                }
            }

            Set<String> countries = countryCache.get(opp.Id);
            Boolean hasUSA = countries != null && countries.contains(COUNTRY_USA);
            Boolean hasHK  = countries != null && countries.contains(COUNTRY_HK);

            if (hasUSA) {
                opp.Billing_Entity__c = BILLING_USA;
                continue;
            } else if (hasHK) {
                opp.Billing_Entity__c = BILLING_HK;
                continue;
            }
            if (String.isNotBlank(opp.LBR_Legal_Entity__c)) {
                String full = opp.LBR_Legal_Entity__c.trim();
                if (fullToAbbrevMap.containsKey(full)) {
                    String abbrev = fullToAbbrevMap.get(full);
                    if (String.isNotBlank(abbrev)) {
                        opp.Billing_Entity__c = abbrev;
                    }
                }
            }
        }
    }
}
