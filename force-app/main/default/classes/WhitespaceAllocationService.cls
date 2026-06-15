/**
 * Gap-to-benchmark headroom allocation engine (architecture §3 / §5).
 *
 * For each Account Plan and product family:
 *     benchmark = benchmarkPerSeat(family, segment) x SoW_Denominator x tierMultiplier(tier)
 *     gap       = max(0, benchmark - owned ARR for that family)
 *
 * The family-level gap is allocated across that family's *addressable* (white-space) cells,
 * weighted by node size, and written to Whitespace_Cell__c.Expected_Revenue__c. Held cells
 * (Owned / In-Renewal / Booked) and N/A cells are zeroed. The Headroom__c / Total_ARR__c roll-ups
 * on Account_Plan__c then reflect real gap math instead of seeded placeholders, and
 * Family_Coverage_Pct__c is recomputed (present cells / applicable cells).
 *
 * Bulk-safe; callable from Apex, Flow (@InvocableMethod) and LWC (via AccountPlanController).
 * The allocation is deterministic and idempotent: re-running over unchanged inputs updates nothing.
 */
public with sharing class WhitespaceAllocationService {

    // Cell states that can receive allocated headroom (genuine white space / pipeline).
    private static final Set<String> GAP_STATES = new Set<String>{
        'White_Space', 'Candidate', 'Win_Back', 'No_Engagement'
    };

    // Code-default tier multipliers; overridable per tier via Plan_Benchmark_Setting__mdt.
    private static final Map<String, Decimal> DEFAULT_TIER_MULTIPLIERS = new Map<String, Decimal>{
        'T1' => 1.0, 'T2' => 0.85, 'T3' => 0.7
    };

    // ---- Entry points -------------------------------------------------------

    /** Flow / Process entry point. Returns one count per invocation (cells updated). */
    @InvocableMethod(label='Recalculate Account Plan Headroom'
                     description='Gap-to-benchmark allocation of Expected Revenue across white-space cells')
    public static List<Integer> allocateInvocable(List<Id> planIds) {
        Set<Id> ids = (planIds == null) ? new Set<Id>() : new Set<Id>(planIds);
        return new List<Integer>{ allocate(ids) };
    }

    /** Public entry point: resolves tier multipliers from CMDT (+ code defaults). */
    public static Integer allocate(Set<Id> planIds) {
        return allocate(planIds, resolveTierMultipliers());
    }

    /**
     * Core engine with injectable tier multipliers (used by tests for determinism).
     * @return number of Whitespace_Cell__c rows updated.
     */
    public static Integer allocate(Set<Id> planIds, Map<String, Decimal> tierMultipliers) {
        if (planIds == null || planIds.isEmpty()) {
            return 0;
        }

        Map<Id, Plan_Product_Family__c> families = new Map<Id, Plan_Product_Family__c>([
            SELECT Id, Benchmark_ARR_Per_Seat_Law_Firm__c, Benchmark_ARR_Per_Seat_Corporate__c
            FROM Plan_Product_Family__c
        ]);

        Map<Id, Account_Plan__c> plans = new Map<Id, Account_Plan__c>([
            SELECT Id, Segment__c, Plan_Tier__c, SoW_Denominator__c, Family_Coverage_Pct__c
            FROM Account_Plan__c
            WHERE Id IN :planIds
        ]);

        Map<Id, List<Whitespace_Cell__c>> cellsByPlan = new Map<Id, List<Whitespace_Cell__c>>();
        for (Whitespace_Cell__c c : [
            SELECT Id, Account_Plan__c, Product_Family__c, Node_Key__c, State__c,
                   ARR__c, Expected_Revenue__c
            FROM Whitespace_Cell__c
            WHERE Account_Plan__c IN :planIds
        ]) {
            if (!cellsByPlan.containsKey(c.Account_Plan__c)) {
                cellsByPlan.put(c.Account_Plan__c, new List<Whitespace_Cell__c>());
            }
            cellsByPlan.get(c.Account_Plan__c).add(c);
        }

        List<Whitespace_Cell__c> cellsToUpdate = new List<Whitespace_Cell__c>();
        List<Account_Plan__c> plansToUpdate = new List<Account_Plan__c>();

        for (Id planId : plans.keySet()) {
            List<Whitespace_Cell__c> cells = cellsByPlan.get(planId);
            if (cells == null || cells.isEmpty()) {
                continue;
            }
            Account_Plan__c plan = plans.get(planId);
            cellsToUpdate.addAll(allocatePlan(plan, cells, families, tierMultipliers));
            plansToUpdate.add(plan);
        }

        if (!cellsToUpdate.isEmpty()) {
            update cellsToUpdate;
        }
        if (!plansToUpdate.isEmpty()) {
            update plansToUpdate;
        }
        return cellsToUpdate.size();
    }

    // ---- Per-plan allocation ------------------------------------------------

    private static List<Whitespace_Cell__c> allocatePlan(
            Account_Plan__c plan,
            List<Whitespace_Cell__c> cells,
            Map<Id, Plan_Product_Family__c> families,
            Map<String, Decimal> tierMultipliers) {

        Boolean isCorporate = (plan.Segment__c == 'Corporate');
        Decimal seats = (plan.SoW_Denominator__c == null) ? 0 : plan.SoW_Denominator__c;
        Decimal tierMult = (tierMultipliers != null && tierMultipliers.containsKey(plan.Plan_Tier__c))
            ? tierMultipliers.get(plan.Plan_Tier__c) : 1.0;

        // Node weights: owned ARR per node (+ the plan average) is the allocation weight, so larger
        // offices/functions draw a bigger share of the gap while every targeted node keeps a baseline.
        Map<String, Decimal> nodeOwned = new Map<String, Decimal>();
        Decimal totalOwned = 0;
        Integer applicable = 0;   // non-N/A cells
        Integer present = 0;      // cells with owned ARR
        for (Whitespace_Cell__c c : cells) {
            Decimal arr = (c.ARR__c == null) ? 0 : c.ARR__c;
            Decimal acc = nodeOwned.containsKey(c.Node_Key__c) ? nodeOwned.get(c.Node_Key__c) : 0;
            nodeOwned.put(c.Node_Key__c, acc + arr);
            totalOwned += arr;
            if (c.State__c != 'NA') applicable++;
            if (arr > 0) present++;
        }
        Decimal avgNodeOwned = (nodeOwned.isEmpty()) ? 0 : totalOwned / nodeOwned.size();

        // Group cells by family.
        Map<Id, List<Whitespace_Cell__c>> byFamily = new Map<Id, List<Whitespace_Cell__c>>();
        for (Whitespace_Cell__c c : cells) {
            if (!byFamily.containsKey(c.Product_Family__c)) {
                byFamily.put(c.Product_Family__c, new List<Whitespace_Cell__c>());
            }
            byFamily.get(c.Product_Family__c).add(c);
        }

        List<Whitespace_Cell__c> changed = new List<Whitespace_Cell__c>();

        for (Id famId : byFamily.keySet()) {
            List<Whitespace_Cell__c> famCells = byFamily.get(famId);

            Decimal perSeat = 0;
            Plan_Product_Family__c fam = families.get(famId);
            if (fam != null) {
                Decimal b = isCorporate ? fam.Benchmark_ARR_Per_Seat_Corporate__c
                                        : fam.Benchmark_ARR_Per_Seat_Law_Firm__c;
                if (b != null) perSeat = b;
            }
            Decimal benchmark = perSeat * seats * tierMult;

            Decimal ownedFamily = 0;
            for (Whitespace_Cell__c c : famCells) {
                ownedFamily += (c.ARR__c == null) ? 0 : c.ARR__c;
            }
            Decimal gap = benchmark - ownedFamily;
            if (gap < 0) gap = 0;

            // Addressable cells + their weights.
            List<Whitespace_Cell__c> addressable = new List<Whitespace_Cell__c>();
            List<Decimal> weights = new List<Decimal>();
            Decimal sumWeights = 0;
            for (Whitespace_Cell__c c : famCells) {
                if (GAP_STATES.contains(c.State__c)) {
                    Decimal w = (nodeOwned.containsKey(c.Node_Key__c) ? nodeOwned.get(c.Node_Key__c) : 0)
                                + avgNodeOwned;
                    if (w <= 0) w = 1;   // floor: a wholly-greenfield node still shares the gap
                    addressable.add(c);
                    weights.add(w);
                    sumWeights += w;
                }
            }

            // Default every family cell to zero headroom, then place the allocation.
            Map<Id, Decimal> alloc = new Map<Id, Decimal>();
            for (Whitespace_Cell__c c : famCells) {
                alloc.put(c.Id, 0);
            }

            if (gap > 0 && !addressable.isEmpty() && sumWeights > 0) {
                Decimal running = 0;
                Integer largestIdx = 0;
                for (Integer i = 0; i < addressable.size(); i++) {
                    Decimal a = (gap * weights[i] / sumWeights).setScale(2, System.RoundingMode.HALF_UP);
                    alloc.put(addressable[i].Id, a);
                    running += a;
                    if (weights[i] > weights[largestIdx]) {
                        largestIdx = i;
                    }
                }
                // Pin the rounding remainder to the largest-weight cell so the parts sum to the gap.
                Decimal remainder = (gap - running).setScale(2, System.RoundingMode.HALF_UP);
                if (remainder != 0) {
                    Id pinId = addressable[largestIdx].Id;
                    alloc.put(pinId, (alloc.get(pinId) + remainder).setScale(2, System.RoundingMode.HALF_UP));
                }
            }

            // Emit only cells whose Expected_Revenue actually changes.
            for (Whitespace_Cell__c c : famCells) {
                Decimal newVal = alloc.get(c.Id);
                Decimal oldVal = (c.Expected_Revenue__c == null) ? 0 : c.Expected_Revenue__c;
                if (oldVal != newVal) {
                    changed.add(new Whitespace_Cell__c(Id = c.Id, Expected_Revenue__c = newVal));
                }
            }
        }

        // Recompute family coverage (present cells / applicable cells).
        plan.Family_Coverage_Pct__c = (applicable > 0)
            ? (Decimal.valueOf(present) * 100 / applicable).setScale(1, System.RoundingMode.HALF_UP)
            : 0;

        return changed;
    }

    // ---- Tier multiplier resolution ----------------------------------------

    private static Map<String, Decimal> resolveTierMultipliers() {
        Map<String, Decimal> result = new Map<String, Decimal>(DEFAULT_TIER_MULTIPLIERS);
        for (Plan_Benchmark_Setting__mdt s : Plan_Benchmark_Setting__mdt.getAll().values()) {
            if (s.Tier_Multiplier__c != null) {
                result.put(s.DeveloperName, s.Tier_Multiplier__c);
            }
        }
        return result;
    }
}
