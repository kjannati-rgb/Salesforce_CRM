/**
 * White-space generation engine (architecture §4).
 *
 * Regenerates Whitespace_Cell__c for an Account Plan from the firm's "owned" entitlement union —
 * turning the matrix from hand-seeded data into a reflection of live CRM ownership. (Gap-to-benchmark
 * headroom allocation was dropped 2026-07-28 — it never had real per-seat benchmark inputs, so it
 * always evaluated to $0; State__c alone now carries the signal.)
 *
 * Grain: plan -> firm Account (Account_Plan__c.Account__c) -> its office Accounts (children via
 * Account.Ultimate_Account__c; the firm itself if it has none). For each office node x segment-relevant
 * product family, owned ARR is summed from the entitlement union and written as a cell. Office_Account__c
 * links each node to its real Account.
 *
 * Product -> family resolves via the SAME commercial-group taxonomy Firm Sales Summary uses
 * (FirmRollupService.resolveGroup / Product_Family_Group__mdt) — Plan_Product_Family__c.Name is expected
 * to equal a Commercial_Group__c value, so a product resolves to one group everywhere in the org rather
 * than two independently-maintained mappings drifting apart.
 *
 * All owned ARR is converted to USD (CurrencyConvUSD, dated FX by Opportunity.CloseDate) before it is
 * written to Whitespace_Cell__c.ARR__c — a lifetime sum of won-Opp line items (Phase 1 definition,
 * unchanged by Phase 2). Only State__c classification was extended below.
 *
 * Office nodes are resolved with the same RecordType='Office' guard as every other consumer of the
 * Ultimate_Account__c firm/office pattern in this org (FirmRollupBatch, LeadMatchSelectService,
 * SmartConvertController). Corporate-segment plans have no Office children by construction, so this
 * guard is segment-safe: they simply fall through to the single-node (firm-as-its-own-node) case below.
 *
 * Phase 2 state model (2026-07-28): State__c now reflects real term/pipeline signals instead of a
 * bare owned/not-owned split. Two term sources are unioned per (node, family), matching the pattern
 * already established in BrandCustomerStatus.forFirm() for brand-level customer status:
 *   - CPQ SBQQ__Subscription__c (SBQQ__StartDate__c / SBQQ__EndDate__c / SBQQ__TerminatedDate__c)
 *   - legacy ALM term dates carried on the won Opportunity itself (Opportunity_Start_Date__c /
 *     Opportunity_End_Date__c) — ALM products predate CPQ subscriptions and never got migrated.
 * The 90-day renewal window matches SalesMotionService.RENEWAL_WINDOW_DAYS (same business definition
 * of "renewing soon", kept as an independent constant since that field is private to its class).
 * "Candidate" pipeline uses the org's existing IsClosed=false definition of open pipeline
 * (FirmSalesSummaryController.getOpenPipeline), restricted to StageName NOT IN ('Identify','Qualify')
 * to exclude the two stages this org's own stage-guidance review found unreliable — deliberately NOT
 * matching on the 'Closed Won – Pending Approval' stage name string, since this org has a documented
 * history of a validation rule that silently never fired from an en-dash/hyphen mismatch on that exact
 * label; IsClosed=false already includes it without needing to spell it out.
 *
 * Auto-signals (2026-07-28): a cell TRANSITIONING into In_Renewal or Win_Back raises an open
 * Plan_Signal__c (Risk / Churn respectively) — see emitTransitionSignals(). Scheduled daily via
 * WhitespaceGenerationSchedule, following the exact pattern already established by
 * PlanSnapshotSchedule/PlanSnapshotService.
 *
 * Continent__c (2026-07-29): macro region (EMEA/North America/APAC/LATAM), resolved from
 * BillingCountry via RegionMappingService/Country_Region__mdt — same shared taxonomy used by
 * FirmSalesSummaryController.OfficeDTO.region. Backs the matrix's "By Region" view.
 *
 * Objective auto-progress (2026-07-29): any Plan_Objective__c with Linked_Family__c set has its
 * Current_Amount__c/Progress_Pct__c recomputed on every regen from the SAME freshly-generated cells
 * (owned ARR summed per plan+family, divided by Target_Amount__c) — see recalcObjectiveProgress().
 * Objectives with no Linked_Family__c are unaffected and stay manually tracked, matching native
 * Salesforce Account Plans' distinction between calc-def-driven and manually-entered measures.
 *
 * Bulk-safe; callable from Apex, Flow (@InvocableMethod) and schedulable wrappers.
 */
public with sharing class WhitespaceGenerationService {

    // Matches SalesMotionService.RENEWAL_WINDOW_DAYS (private to that class, so redeclared here).
    @TestVisible private static final Integer RENEWAL_WINDOW_DAYS = 90;

    /** Per (node|family) key: term + pipeline signals used to classify State__c. */
    @TestVisible
    private class CellSignal {
        @TestVisible Boolean hasHistory = false;
        @TestVisible Date activeTermEnd;        // earliest end date of a term covering today (null = none active)
        @TestVisible Boolean hasFutureTerm = false;   // a term starts after today (signed, not yet live)
        @TestVisible Date earliestLapsedEnd;    // most recent end/termination date of a term that has already lapsed
        @TestVisible Boolean hasCandidateOpenOpp = false;
    }

    @InvocableMethod(label='Generate Account Plan White-Space'
                     description='Regenerate white-space cells from owned entitlements and live term/pipeline signals')
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
        for (Account a : [SELECT Id, Name, Ultimate_Account__c, BillingCity, BillingCountry FROM Account
                          WHERE Ultimate_Account__c IN :firmIds AND RecordType.DeveloperName = 'Office']) {
            nodesByFirm.get(a.Ultimate_Account__c).add(a);
        }
        for (Account a : [SELECT Id, Name, BillingCity, BillingCountry FROM Account WHERE Id IN :firmIds]) {
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

        // Product family catalogue, keyed by commercial-group name (Plan_Product_Family__c.Name is
        // expected to equal a Product_Family_Group__mdt.Commercial_Group__c value — see class header).
        List<Plan_Product_Family__c> families = [
            SELECT Id, Name, Relevant_Law_Firm__c, Relevant_Corporate__c
            FROM Plan_Product_Family__c
        ];
        Map<String, Plan_Product_Family__c> familyByGroup = new Map<String, Plan_Product_Family__c>();
        for (Plan_Product_Family__c f : families) {
            familyByGroup.put(f.Name.toLowerCase(), f);
        }

        Map<String, CellSignal> signalsByCell = new Map<String, CellSignal>();
        Map<String, Decimal> ownedByCell = collectOwnedArr(nodeAccountIds, familyByGroup, signalsByCell);
        collectSubscriptionSignals(nodeAccountIds, familyByGroup, signalsByCell);

        Date today = Date.today();
        Date renewalCutoff = today.addDays(RENEWAL_WINDOW_DAYS);

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
                    String key = node.Id + '|' + f.Id;
                    Decimal owned = ownedByCell.get(key);
                    if (owned == null) {
                        owned = 0;
                    }
                    CellSignal sig = signalsByCell.get(key);
                    Whitespace_Cell__c cell = new Whitespace_Cell__c(
                        Account_Plan__c = planId,
                        Product_Family__c = f.Id,
                        Office_Account__c = node.Id,
                        Node_Type__c = 'Office_Subsidiary',
                        Node_Key__c = String.valueOf(node.Id),
                        Node_Label__c = node.Name,
                        Region__c = formatRegion(node.BillingCity, node.BillingCountry),
                        Continent__c = RegionMappingService.regionFor(node.BillingCountry),
                        State__c = resolveState(owned, sig, today, renewalCutoff),
                        ARR__c = owned,
                        Next_Action__c = 'Auto-generated',
                        External_Key__c = planId + '|' + f.Id + '|' + node.Id);
                    // ARR__c is already USD-converted above — stamp the record's own currency to match,
                    // else it silently inherits the creating user's currency (e.g. GBP) as a label on a
                    // USD number, which double-converts on any downstream report/SOQL convertCurrency().
                    cell.CurrencyIsoCode = 'USD';
                    toInsert.add(cell);
                }
            }
        }

        // Regenerate: replace the plan's cells with the freshly-computed set, capturing each cell's
        // prior state first (keyed by the stable External_Key__c, since the Id itself doesn't survive
        // the delete/insert) so a transition into a risk state can be signalled below.
        Map<String, String> oldStateByKey = new Map<String, String>();
        if (!regenPlanIds.isEmpty()) {
            List<Whitespace_Cell__c> oldCells = [
                SELECT Id, External_Key__c, State__c
                FROM Whitespace_Cell__c WHERE Account_Plan__c IN :regenPlanIds
            ];
            for (Whitespace_Cell__c c : oldCells) {
                oldStateByKey.put(c.External_Key__c, c.State__c);
            }
            delete oldCells;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        Map<Id, String> familyNameById = new Map<Id, String>();
        for (Plan_Product_Family__c f : families) {
            familyNameById.put(f.Id, f.Name);
        }
        emitTransitionSignals(toInsert, oldStateByKey, familyNameById);
        recalcObjectiveProgress(toInsert, regenPlanIds);

        return toInsert.size();
    }

    /**
     * Auto-raises a Plan_Signal__c the moment a cell TRANSITIONS into In_Renewal (Risk) or Win_Back
     * (Churn) — comparing against the prior state means an unchanging risk doesn't get re-flagged every
     * time the daily schedule regenerates the matrix, it only fires the day the state actually changes.
     * An open-Summary__c dedupe guard is a secondary safety net against double-firing if generate() is
     * ever invoked twice for the same plan in one day.
     */
    @TestVisible
    private static void emitTransitionSignals(
            List<Whitespace_Cell__c> newCells,
            Map<String, String> oldStateByKey,
            Map<Id, String> familyNameById) {
        List<Plan_Signal__c> candidates = new List<Plan_Signal__c>();
        for (Whitespace_Cell__c c : newCells) {
            String oldState = oldStateByKey.get(c.External_Key__c);
            if (oldState == c.State__c) {
                continue; // no transition — including "still In_Renewal/Win_Back from yesterday"
            }
            String famName = familyNameById.get(c.Product_Family__c);
            if (c.State__c == 'In_Renewal') {
                candidates.add(new Plan_Signal__c(
                    Account_Plan__c = c.Account_Plan__c, Signal_Type__c = 'Risk', Severity__c = 'Medium',
                    Source__c = 'Whitespace_Cell', Status__c = 'Open', Detected_Date__c = Date.today(),
                    Linked_Cell__c = c.Id,
                    Summary__c = c.Node_Label__c + ' — ' + famName + ' renews within 90 days',
                    Recommended_Action__c = 'Schedule a renewal conversation before the contract lapses.'));
            } else if (c.State__c == 'Win_Back') {
                candidates.add(new Plan_Signal__c(
                    Account_Plan__c = c.Account_Plan__c, Signal_Type__c = 'Churn', Severity__c = 'High',
                    Source__c = 'Whitespace_Cell', Status__c = 'Open', Detected_Date__c = Date.today(),
                    Linked_Cell__c = c.Id,
                    Summary__c = c.Node_Label__c + ' — ' + famName + ' has lapsed with no renewal',
                    Recommended_Action__c = 'Re-engage this office to win back the relationship.'));
            }
        }
        if (candidates.isEmpty()) {
            return;
        }

        Set<Id> planIds = new Set<Id>();
        for (Plan_Signal__c s : candidates) {
            planIds.add(s.Account_Plan__c);
        }
        Set<String> alreadyOpen = new Set<String>();
        for (Plan_Signal__c s : [
            SELECT Account_Plan__c, Summary__c FROM Plan_Signal__c
            WHERE Account_Plan__c IN :planIds AND Status__c = 'Open'
        ]) {
            alreadyOpen.add(s.Account_Plan__c + '|' + s.Summary__c);
        }

        List<Plan_Signal__c> toInsert = new List<Plan_Signal__c>();
        for (Plan_Signal__c s : candidates) {
            if (!alreadyOpen.contains(s.Account_Plan__c + '|' + s.Summary__c)) {
                toInsert.add(s);
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * Recomputes Current_Amount__c / Progress_Pct__c for every Plan_Objective__c linked to a product
     * family, from the SAME cells just written by generate() — no extra Whitespace_Cell__c query needed.
     * Objectives with no Linked_Family__c are left untouched (still manually tracked). Progress is not
     * capped at 100 — an over-achieved objective legitimately shows over 100%, matching how the org
     * already reports over-quota attainment elsewhere; the UI progress bar clamps the visual fill only.
     */
    @TestVisible
    private static void recalcObjectiveProgress(List<Whitespace_Cell__c> newCells, List<Id> regenPlanIds) {
        if (regenPlanIds.isEmpty()) {
            return;
        }

        Map<String, Decimal> arrByPlanFamily = new Map<String, Decimal>();
        for (Whitespace_Cell__c c : newCells) {
            String key = c.Account_Plan__c + '|' + c.Product_Family__c;
            Decimal running = arrByPlanFamily.get(key);
            Decimal cellArr = (c.ARR__c == null) ? 0 : c.ARR__c;
            arrByPlanFamily.put(key, (running == null ? 0 : running) + cellArr);
        }

        List<Plan_Objective__c> toUpdate = new List<Plan_Objective__c>();
        for (Plan_Objective__c o : [
            SELECT Id, Account_Plan__c, Linked_Family__c, Target_Amount__c, Current_Amount__c, Progress_Pct__c
            FROM Plan_Objective__c
            WHERE Account_Plan__c IN :regenPlanIds AND Linked_Family__c != null
        ]) {
            Decimal current = arrByPlanFamily.get(o.Account_Plan__c + '|' + o.Linked_Family__c);
            if (current == null) {
                current = 0;
            }
            Decimal pct = (o.Target_Amount__c != null && o.Target_Amount__c > 0)
                ? (current / o.Target_Amount__c * 100).setScale(1)
                : 0;
            if (o.Current_Amount__c != current || o.Progress_Pct__c != pct) {
                o.Current_Amount__c = current;
                o.Progress_Pct__c = pct;
                toUpdate.add(o);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /** Office display location, e.g. "London, United Kingdom" — City-only or Country-only if the other is blank. */
    private static String formatRegion(String city, String country) {
        if (String.isNotBlank(city) && String.isNotBlank(country)) {
            return city + ', ' + country;
        }
        return String.isNotBlank(city) ? city : country;
    }

    /**
     * State precedence for one (node, family) cell — first match wins. Term-date signals
     * (active / future / lapsed) are authoritative and checked first; the bare "owned > 0" lifetime-ARR
     * fallback only applies when there's no term-date signal at all, so a confirmed lapse always beats
     * stale historical revenue instead of being masked by it.
     */
    @TestVisible
    private static String resolveState(Decimal owned, CellSignal sig, Date today, Date renewalCutoff) {
        if (sig != null && sig.activeTermEnd != null && sig.activeTermEnd <= renewalCutoff) {
            return 'In_Renewal';
        }
        if (sig != null && sig.activeTermEnd != null) {
            return 'Owned_Healthy';
        }
        if (sig != null && sig.hasFutureTerm) {
            return 'Booked';
        }
        if (sig != null && sig.earliestLapsedEnd != null) {
            return 'Win_Back';
        }
        if (owned > 0) {
            return 'Owned_Healthy';
        }
        if (sig != null && sig.hasCandidateOpenOpp) {
            return 'Candidate';
        }
        if (sig == null || !sig.hasHistory) {
            return 'No_Engagement';
        }
        return 'White_Space';
    }

    /**
     * The "owned" entitlement union, keyed by "accountId|familyId" -> summed ARR (won-Opp lifetime
     * total, Phase 1 definition, unchanged). Also populates signalsByCell with term/pipeline signals
     * from the SAME query: legacy ALM term dates live on the Opportunity itself
     * (Opportunity_Start_Date__c / Opportunity_End_Date__c — see BrandCustomerStatus.forFirm()), and
     * open-pipeline "Candidate" signal reuses the org's IsClosed=false definition of open pipeline.
     */
    private static Map<String, Decimal> collectOwnedArr(
            Set<Id> nodeAccountIds,
            Map<String, Plan_Product_Family__c> familyByGroup,
            Map<String, CellSignal> signalsByCell) {
        Map<String, Decimal> owned = new Map<String, Decimal>();
        if (nodeAccountIds.isEmpty()) {
            return owned;
        }
        Date today = Date.today();
        for (OpportunityLineItem oli : [
            SELECT Opportunity.AccountId, Opportunity.CloseDate, Opportunity.IsWon, Opportunity.IsClosed,
                   Opportunity.StageName, Opportunity.Opportunity_Start_Date__c, Opportunity.Opportunity_End_Date__c,
                   CurrencyIsoCode, TotalPrice, Product2.Family, Product2.Product_Type__c
            FROM OpportunityLineItem
            WHERE Opportunity.AccountId IN :nodeAccountIds
        ]) {
            if (oli.Product2 == null) {
                continue;
            }
            String grp = FirmRollupService.resolveGroup(oli.Product2.Family, oli.Product2.Product_Type__c);
            Plan_Product_Family__c fam = familyByGroup.get(grp.toLowerCase());
            if (fam == null) {
                continue;
            }
            String key = oli.Opportunity.AccountId + '|' + fam.Id;
            CellSignal sig = signalsByCell.get(key);
            if (sig == null) {
                sig = new CellSignal();
                signalsByCell.put(key, sig);
            }
            sig.hasHistory = true;

            if (oli.Opportunity.IsWon) {
                Decimal amt = (oli.TotalPrice == null) ? 0 : oli.TotalPrice;
                Decimal amtUsd = CurrencyConvUSD.toUSD(amt, oli.CurrencyIsoCode, oli.Opportunity.CloseDate);
                owned.put(key, (owned.containsKey(key) ? owned.get(key) : 0) + amtUsd);

                Date s = oli.Opportunity.Opportunity_Start_Date__c;
                Date e = oli.Opportunity.Opportunity_End_Date__c;
                if (s != null && e != null) {
                    if (s <= today && e >= today) {
                        if (sig.activeTermEnd == null || e < sig.activeTermEnd) sig.activeTermEnd = e;
                    } else if (s > today) {
                        sig.hasFutureTerm = true;
                    } else if (e < today) {
                        if (sig.earliestLapsedEnd == null || e > sig.earliestLapsedEnd) sig.earliestLapsedEnd = e;
                    }
                }
            } else if (!oli.Opportunity.IsClosed
                    && oli.Opportunity.StageName != 'Identify'
                    && oli.Opportunity.StageName != 'Qualify') {
                sig.hasCandidateOpenOpp = true;
            }
        }
        return owned;
    }

    /** CPQ subscription term signals (SBQQ__Subscription__c), unioned into the same signalsByCell map. */
    private static void collectSubscriptionSignals(
            Set<Id> nodeAccountIds,
            Map<String, Plan_Product_Family__c> familyByGroup,
            Map<String, CellSignal> signalsByCell) {
        if (nodeAccountIds.isEmpty()) {
            return;
        }
        Date today = Date.today();
        for (SBQQ__Subscription__c sub : [
            SELECT SBQQ__Account__c, SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__TerminatedDate__c,
                   SBQQ__Product__r.Family, SBQQ__Product__r.Product_Type__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Account__c IN :nodeAccountIds
        ]) {
            if (sub.SBQQ__Product__r == null) {
                continue;
            }
            String grp = FirmRollupService.resolveGroup(sub.SBQQ__Product__r.Family, sub.SBQQ__Product__r.Product_Type__c);
            Plan_Product_Family__c fam = familyByGroup.get(grp.toLowerCase());
            if (fam == null) {
                continue;
            }
            String key = sub.SBQQ__Account__c + '|' + fam.Id;
            CellSignal sig = signalsByCell.get(key);
            if (sig == null) {
                sig = new CellSignal();
                signalsByCell.put(key, sig);
            }
            sig.hasHistory = true;

            Date s = sub.SBQQ__StartDate__c;
            Date e = sub.SBQQ__EndDate__c;
            if (s == null || e == null) {
                continue;
            }
            Boolean terminatedEarly = sub.SBQQ__TerminatedDate__c != null;
            if (!terminatedEarly && s <= today && e >= today) {
                if (sig.activeTermEnd == null || e < sig.activeTermEnd) sig.activeTermEnd = e;
            } else if (!terminatedEarly && s > today) {
                sig.hasFutureTerm = true;
            } else {
                Date lapseDate = terminatedEarly ? sub.SBQQ__TerminatedDate__c : e;
                if (sig.earliestLapsedEnd == null || lapseDate > sig.earliestLapsedEnd) sig.earliestLapsedEnd = lapseDate;
            }
        }
    }
}
