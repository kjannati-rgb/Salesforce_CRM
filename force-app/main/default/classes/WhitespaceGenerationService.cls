/**
 * White-space generation engine (architecture §4).
 *
 * Regenerates Whitespace_Cell__c for an Account Plan from the firm's "owned" entitlement union, then
 * chains the gap-to-benchmark allocation so headroom recomputes — turning the matrix from hand-seeded
 * data into a reflection of live CRM ownership.
 *
 * Grain: plan -> firm Account (Account_Plan__c.Account__c) -> its office Accounts (children via
 * Account.Ultimate_Account__c; the firm itself if it has none). For each office node x segment-relevant
 * product family, owned ARR is summed from the entitlement union and written as a cell (Owned / Healthy
 * where owned, White Space where not). Office_Account__c links each node to its real Account.
 *
 * Phase 1 source = won Opportunities + their line items (universal, no CPQ dependency). The union is
 * designed to extend to CPQ subscriptions (SBQQ__Subscription__c) and active Contracts — add them to
 * collectOwnedArr() keyed the same way. Product -> family resolves via Plan_Product_Family__c.
 * CPQ_Family_Mapping__c (falling back to the family Name).
 *
 * Bulk-safe; callable from Apex, Flow (@InvocableMethod) and schedulable wrappers.
 */
public with sharing class WhitespaceGenerationService {

    @InvocableMethod(label='Generate Account Plan White-Space'
                     description='Regenerate white-space cells from owned entitlements, then recompute headroom')
    public static List<Integer> generateInvocable(List<Id> planIds) {
        Set<Id> ids = (planIds == null) ? new Set<Id>() : new Set<Id>(planIds);
        return new List<Integer>{ generate(ids) };
    }

    /** @return number of Whitespace_Cell__c rows generated. */
    public static Integer generate(Set<Id> planIds) {
        if (planIds == null || planIds.isEmpty()) {
            return 0;
        }

        Map<Id, Account_Plan__c> plans = new Map<Id, Account_Plan__c>([
            SELECT Id, Account__c, Segment__c
            FROM Account_Plan__c
            WHERE Id IN :planIds AND Account__c != null
        ]);
        if (plans.isEmpty()) {
            return 0;
        }

        // Firm -> office node Accounts: children via Ultimate_Account__c, or the firm itself if none.
        Set<Id> firmIds = new Set<Id>();
        for (Account_Plan__c p : plans.values()) {
            firmIds.add(p.Account__c);
        }
        Map<Id, List<Account>> nodesByFirm = new Map<Id, List<Account>>();
        for (Id f : firmIds) {
            nodesByFirm.put(f, new List<Account>());
        }
        for (Account a : [SELECT Id, Name, Ultimate_Account__c FROM Account WHERE Ultimate_Account__c IN :firmIds]) {
            nodesByFirm.get(a.Ultimate_Account__c).add(a);
        }
        for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :firmIds]) {
            if (nodesByFirm.get(a.Id).isEmpty()) {
                nodesByFirm.get(a.Id).add(a);   // single-account firm (e.g. corporate) is its own node
            }
        }

        Set<Id> nodeAccountIds = new Set<Id>();
        for (List<Account> ns : nodesByFirm.values()) {
            for (Account a : ns) {
                nodeAccountIds.add(a.Id);
            }
        }

        // Product family catalogue + lookup (by CPQ mapping code, falling back to family name).
        List<Plan_Product_Family__c> families = [
            SELECT Id, Name, CPQ_Family_Mapping__c, Relevant_Law_Firm__c, Relevant_Corporate__c
            FROM Plan_Product_Family__c
        ];
        Map<String, Plan_Product_Family__c> familyByKey = new Map<String, Plan_Product_Family__c>();
        for (Plan_Product_Family__c f : families) {
            familyByKey.put(f.Name.toLowerCase(), f);
            if (String.isNotBlank(f.CPQ_Family_Mapping__c)) {
                familyByKey.put(f.CPQ_Family_Mapping__c.toLowerCase(), f);
            }
        }

        Map<String, Decimal> ownedByCell = collectOwnedArr(nodeAccountIds, familyByKey);

        // Build the regenerated grid.
        List<Whitespace_Cell__c> toInsert = new List<Whitespace_Cell__c>();
        List<Id> regenPlanIds = new List<Id>();
        for (Id planId : plans.keySet()) {
            Account_Plan__c p = plans.get(planId);
            List<Account> nodes = nodesByFirm.get(p.Account__c);
            if (nodes == null || nodes.isEmpty()) {
                continue;
            }
            regenPlanIds.add(planId);
            Boolean isCorporate = (p.Segment__c == 'Corporate');
            for (Account node : nodes) {
                for (Plan_Product_Family__c f : families) {
                    Boolean relevant = isCorporate ? f.Relevant_Corporate__c : f.Relevant_Law_Firm__c;
                    if (relevant != true) {
                        continue;
                    }
                    Decimal owned = ownedByCell.get(node.Id + '|' + f.Id);
                    if (owned == null) {
                        owned = 0;
                    }
                    toInsert.add(new Whitespace_Cell__c(
                        Account_Plan__c = planId,
                        Product_Family__c = f.Id,
                        Office_Account__c = node.Id,
                        Node_Type__c = 'Office_Subsidiary',
                        Node_Key__c = String.valueOf(node.Id),
                        Node_Label__c = node.Name,
                        State__c = (owned > 0) ? 'Owned_Healthy' : 'White_Space',
                        ARR__c = owned,
                        Expected_Revenue__c = 0,
                        Next_Action__c = 'Auto-generated',
                        External_Key__c = planId + '|' + f.Id + '|' + node.Id));
                }
            }
        }

        // Regenerate: replace the plan's cells, then recompute headroom.
        if (!regenPlanIds.isEmpty()) {
            delete [SELECT Id FROM Whitespace_Cell__c WHERE Account_Plan__c IN :regenPlanIds];
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        WhitespaceAllocationService.allocate(plans.keySet());
        return toInsert.size();
    }

    /**
     * The "owned" entitlement union, keyed by "accountId|familyId" -> summed ARR.
     * Phase 1: won Opportunity line items. Extend here with CPQ subscriptions / active contracts,
     * deduping so recurring revenue is not double-counted across sources.
     */
    private static Map<String, Decimal> collectOwnedArr(Set<Id> nodeAccountIds, Map<String, Plan_Product_Family__c> familyByKey) {
        Map<String, Decimal> owned = new Map<String, Decimal>();
        if (nodeAccountIds.isEmpty()) {
            return owned;
        }
        for (OpportunityLineItem oli : [
            SELECT Opportunity.AccountId, TotalPrice, Product2.Name, Product2.Family
            FROM OpportunityLineItem
            WHERE Opportunity.IsWon = true AND Opportunity.AccountId IN :nodeAccountIds
        ]) {
            Plan_Product_Family__c fam;
            if (oli.Product2 != null) {
                if (String.isNotBlank(oli.Product2.Family)) {
                    fam = familyByKey.get(oli.Product2.Family.toLowerCase());
                }
                if (fam == null && String.isNotBlank(oli.Product2.Name)) {
                    fam = familyByKey.get(oli.Product2.Name.toLowerCase());
                }
            }
            if (fam == null) {
                continue;
            }
            String key = oli.Opportunity.AccountId + '|' + fam.Id;
            Decimal amt = (oli.TotalPrice == null) ? 0 : oli.TotalPrice;
            owned.put(key, (owned.containsKey(key) ? owned.get(key) : 0) + amt);
        }
        return owned;
    }
}
