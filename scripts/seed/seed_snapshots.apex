/*
 * Seed backdated Plan_Snapshot__c history for the demo plans so the Headroom Trend (§10) renders a
 * QBR story: owned ARR rising, headroom falling as white space converts. Idempotent (upsert by
 * External_Key). Run AFTER the §10 metadata is deployed and the demo plans exist.
 *   sf apex run --file scripts/seed/seed_snapshots.apex --target-org KJDEV
 */

Map<String, Map<Integer, List<Decimal>>> demo = new Map<String, Map<Integer, List<Decimal>>>{
    // planName => { daysAgo => [TotalARR, Headroom, Coverage%] }
    'Globex Legal (DEMO) - Account Plan' => new Map<Integer, List<Decimal>>{
        90 => new List<Decimal>{ 420000, 620000, 35 },
        60 => new List<Decimal>{ 470000, 560000, 38 },
        30 => new List<Decimal>{ 510000, 510000, 40 },
        0  => new List<Decimal>{ 541000, 464800, 41.2 }
    },
    'Demo Corp Alpha - Legal & Compliance' => new Map<Integer, List<Decimal>>{
        90 => new List<Decimal>{ 300000, 410000, 28 },
        60 => new List<Decimal>{ 320000, 385000, 30 },
        30 => new List<Decimal>{ 340000, 360000, 32 },
        0  => new List<Decimal>{ 354000, 339275, 33.3 }
    }
};

Map<String, Account_Plan__c> planByName = new Map<String, Account_Plan__c>();
for (Account_Plan__c p : [SELECT Id, Name, Plan_Tier__c, Segment__c FROM Account_Plan__c WHERE Name IN :demo.keySet()]) {
    planByName.put(p.Name, p);
}

List<Plan_Snapshot__c> snaps = new List<Plan_Snapshot__c>();
for (String name : demo.keySet()) {
    Account_Plan__c p = planByName.get(name);
    if (p == null) continue;
    for (Integer daysAgo : demo.get(name).keySet()) {
        List<Decimal> v = demo.get(name).get(daysAgo);
        Date d = Date.today().addDays(-daysAgo);
        snaps.add(new Plan_Snapshot__c(
            Account_Plan__c = p.Id,
            Snapshot_Date__c = d,
            Total_ARR__c = v[0],
            Headroom__c = v[1],
            Family_Coverage_Pct__c = v[2],
            Plan_Tier__c = p.Plan_Tier__c,
            Segment__c = p.Segment__c,
            External_Key__c = p.Id + '|' + String.valueOf(d)));
    }
}
upsert snaps Plan_Snapshot__c.External_Key__c;
System.debug('Seeded ' + snaps.size() + ' snapshots across ' + planByName.size() + ' plans.');
