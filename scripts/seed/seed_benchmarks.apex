/*
 * Seed gap-to-benchmark inputs (architecture §3 / §5), then run the allocation engine so the
 * demo plans' Expected_Revenue / Headroom reflect real gap math instead of seeded placeholders.
 *
 * Run AFTER seed_account_plans.apex:
 *   sf apex run --file scripts/seed/seed_benchmarks.apex --target-org KJDEV
 *
 * Idempotent: re-running re-stamps the benchmarks and re-allocates (a no-op if nothing changed).
 */

// 1) Per-seat benchmark by family: { Law Firm per attorney, Corporate per in-house counsel }. Tune freely.
Map<String, List<Decimal>> bench = new Map<String, List<Decimal>>{
    'Lexology PRO'          => new List<Decimal>{ 1500, 1500 },
    'Specialist Platforms'  => new List<Decimal>{ 600,  700  },
    'Lexology Intelligence' => new List<Decimal>{ 700,  900  },
    'ALM Subs / IS'         => new List<Decimal>{ 500,  500  },
    'Events & Sponsorship'  => new List<Decimal>{ 200,  150  },
    'Advertising'           => new List<Decimal>{ 150,  0    }
};

List<Plan_Product_Family__c> fams = [
    SELECT Id, Name FROM Plan_Product_Family__c WHERE Name IN :bench.keySet()];
for (Plan_Product_Family__c f : fams) {
    List<Decimal> b = bench.get(f.Name);
    f.Benchmark_ARR_Per_Seat_Law_Firm__c  = b[0];
    f.Benchmark_ARR_Per_Seat_Corporate__c = b[1];
}
update fams;
System.debug('Benchmarked ' + fams.size() + ' families.');

// 2) Run the engine on the demo plans (tier multipliers come from Plan_Benchmark_Setting__mdt).
Set<Id> planIds = new Map<Id, Account_Plan__c>([
    SELECT Id FROM Account_Plan__c
    WHERE Name IN ('Globex Legal (DEMO) - Account Plan', 'Demo Corp Alpha - Legal & Compliance')
]).keySet();
Integer updated = WhitespaceAllocationService.allocate(planIds);
System.debug('Allocated headroom across ' + updated + ' cells for ' + planIds.size() + ' plans.');

// 3) Echo the recomputed plan-level figures.
for (Account_Plan__c p : [
    SELECT Name, Plan_Tier__c, SoW_Denominator__c, Total_ARR__c, Headroom__c, Family_Coverage_Pct__c
    FROM Account_Plan__c WHERE Id IN :planIds ORDER BY Name]) {
    System.debug(p.Name + ' [' + p.Plan_Tier__c + ', ' + p.SoW_Denominator__c + ' seats]'
        + '  Owned=' + p.Total_ARR__c
        + '  Headroom=' + p.Headroom__c
        + '  Coverage=' + p.Family_Coverage_Pct__c + '%');
}
