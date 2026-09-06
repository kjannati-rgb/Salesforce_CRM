/*
 * Seed product groups and assign the demo families, so the matrix shows grouped, collapsible column
 * bands. Idempotent. Run AFTER the Plan_Product_Group__c metadata is deployed.
 *   sf apex run --file scripts/seed/seed_product_groups.apex --target-org KJDEV
 */

Map<String, Decimal> groups = new Map<String, Decimal>{ 'Subscriptions' => 1, 'Events & Media' => 2 };
Map<String, Id> gid = new Map<String, Id>();
for (Plan_Product_Group__c g : [SELECT Id, Name FROM Plan_Product_Group__c WHERE Name IN :groups.keySet()]) {
    gid.put(g.Name, g.Id);
}
List<Plan_Product_Group__c> newGroups = new List<Plan_Product_Group__c>();
for (String n : groups.keySet()) {
    if (!gid.containsKey(n)) newGroups.add(new Plan_Product_Group__c(Name = n, Sort_Order__c = groups.get(n), Active__c = true));
}
if (!newGroups.isEmpty()) {
    insert newGroups;
    for (Plan_Product_Group__c g : newGroups) gid.put(g.Name, g.Id);
}

Map<String, String> famGroup = new Map<String, String>{
    'Lexology PRO' => 'Subscriptions',
    'Specialist Platforms' => 'Subscriptions',
    'Lexology Intelligence' => 'Subscriptions',
    'ALM Subs / IS' => 'Subscriptions',
    'Events & Sponsorship' => 'Events & Media',
    'Advertising' => 'Events & Media'
};
List<Plan_Product_Family__c> fams = [SELECT Id, Name FROM Plan_Product_Family__c WHERE Name IN :famGroup.keySet()];
for (Plan_Product_Family__c f : fams) {
    f.Product_Group__c = gid.get(famGroup.get(f.Name));
    f.Active__c = true;
}
update fams;
System.debug('Grouped ' + fams.size() + ' families into ' + gid.size() + ' groups.');
