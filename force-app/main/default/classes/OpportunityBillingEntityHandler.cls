public class OpportunityBillingEntityHandler {

    private static final Set<String> TYPE_RENEWALS           = new Set<String>{'Renewal', 'Auto-Renewal'};
    private static final Set<String> TYPE_REPEAT_BUSINESS    = new Set<String>{'Repeat Business', 'Auto-Repeat Business'};

    private static final String COUNTRY_USA = 'United States';
    private static final String COUNTRY_HK  = 'Hong Kong';

    private static final String BILLING_USA = 'LLC';
    private static final String BILLING_HK  = 'GHK';

    public static void evaluate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        System.debug('newList'+newList);
        System.debug('oldMap'+oldMap);
        Set<Id> oppIdsNeedingOLI   = new Set<Id>();
        Set<Id> oppIdsNeedingPrev  = new Set<Id>();

        for (Opportunity opp : newList) {
            System.debug('opp.Type'+opp.Type);
            String typeVal = (opp.Type == null) ? null : opp.Type.trim();
			System.debug('typeVal'+typeVal);
            Boolean shouldRun = true;
            if (Trigger.isUpdate) {
                Opportunity oldOpp = oldMap.get(opp.Id);
                System.debug('oldOpp.No_of_Line_Items__c'+oldOpp.No_of_Line_Items__c);
                System.debug('opp.No_of_Line_Items__c'+opp.No_of_Line_Items__c);
                System.debug('oldOpp.Type'+oldOpp.Type);
                Boolean countChanged = oldOpp.No_of_Line_Items__c != opp.No_of_Line_Items__c;
                Boolean typeChanged  = oldOpp.Type != opp.Type;
                Boolean preOppChanged  = (oldOpp.Previous_Opportunity__c == null)  && (oldOpp.Previous_Opportunity__c != opp.Previous_Opportunity__c);
                Boolean blankWithLineItems = String.isBlank(opp.Billing_Entity__c) && opp.No_of_Line_Items__c != null && opp.No_of_Line_Items__c > 0;
                shouldRun = countChanged || typeChanged || preOppChanged || blankWithLineItems;
                System.debug('shouldRun'+shouldRun);
            }

            if (!shouldRun) continue;

            if (typeVal != null && TYPE_RENEWALS.contains(typeVal) && opp.Previous_Opportunity__c != null) {
                System.debug('opp.Previous_Opportunity__c'+opp.Previous_Opportunity__c);
                oppIdsNeedingPrev.add(opp.Previous_Opportunity__c);
            }
			System.debug('opp.Id'+opp.Id);
            if (opp.Id != null) {
                oppIdsNeedingOLI.add(opp.Id);
            }
			System.debug('opp.Previous_Opportunity__c'+opp.Previous_Opportunity__c);
            if (typeVal != null && TYPE_REPEAT_BUSINESS.contains(typeVal) && opp.Previous_Opportunity__c != null) {
                oppIdsNeedingPrev.add(opp.Previous_Opportunity__c);
            }
        }
        System.debug('oppIdsNeedingPrev'+oppIdsNeedingPrev);
        System.debug('oppIdsNeedingOLI'+oppIdsNeedingOLI);

        Map<Id, Opportunity> prevOppIdToOpp = new Map<Id, Opportunity>();
        if (!oppIdsNeedingPrev.isEmpty()) {
            prevOppIdToOpp = new Map<Id, Opportunity>([SELECT Id, Billing_Entity__c, IsClosed FROM Opportunity WHERE Id IN :oppIdsNeedingPrev]);
        }
		System.debug('prevOppIdToOpp'+prevOppIdToOpp);
        Map<Id, Set<String>> oppIdToCountries = new Map<Id, Set<String>>();
        if (!oppIdsNeedingOLI.isEmpty()) {
            for (OpportunityLineItem oli : [SELECT OpportunityId, Product2.Event_Location_Country__c FROM OpportunityLineItem
                                            WHERE OpportunityId IN :oppIdsNeedingOLI]) {

                if (oli.OpportunityId == null) continue;

                if (!oppIdToCountries.containsKey(oli.OpportunityId)) {
                    oppIdToCountries.put(oli.OpportunityId, new Set<String>());
                }

                String ctry = (oli.Product2 != null) ? oli.Product2.Event_Location_Country__c : null;

                if (String.isNotBlank(ctry)) {
                    oppIdToCountries.get(oli.OpportunityId).add(ctry.trim());
                }
            }
        }
		System.debug('oppIdToCountries'+oppIdToCountries);
        Map<String, String> fullToAbbrevMap = new Map<String, String>();
        for (Opportunity_Billing_Entity_Mapping__c cs : [SELECT Full_Billing_Entity_Name__c, Abbreviation_Billing_Entity_Name__c
                                                         FROM Opportunity_Billing_Entity_Mapping__c ]) {
            if (String.isNotBlank(cs.Full_Billing_Entity_Name__c)) {
                fullToAbbrevMap.put(cs.Full_Billing_Entity_Name__c.trim(), cs.Abbreviation_Billing_Entity_Name__c);
            }
        }
		System.debug('fullToAbbrevMap'+fullToAbbrevMap);
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
                    Opportunity prevOpp = prevOppIdToOpp.get(opp.Previous_Opportunity__c);
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
                    Opportunity prevOpp = prevOppIdToOpp.get(opp.Previous_Opportunity__c);
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

            Set<String> countries = oppIdToCountries.get(opp.Id);
            Boolean hasUSA = countries != null && countries.contains(COUNTRY_USA);
            Boolean hasHK  = countries != null && countries.contains(COUNTRY_HK);

            if (hasUSA) {
                opp.Billing_Entity__c = BILLING_USA;
                continue;
            } else if (hasHK) {
                opp.Billing_Entity__c = BILLING_HK;
                continue;
            }
			System.debug('opp.LBR_Legal_Entity__c'+opp.LBR_Legal_Entity__c);
            if (String.isNotBlank(opp.LBR_Legal_Entity__c)) {
                String full = opp.LBR_Legal_Entity__c.trim();
                if (fullToAbbrevMap.containsKey(full)) {
                    String abbrev = fullToAbbrevMap.get(full);
                    if (String.isNotBlank(abbrev)) {
                        opp.Billing_Entity__c = abbrev;
                    }
                }
            }
            System.debug('opp.Billing_Entity__c'+opp.Billing_Entity__c);
        }
    }
}
