// Real PROD Product2.Division__c taxonomy, cross-referenced against Product_Family_Group__mdt
// (Family__c -> Commercial_Group__c) to assign each of the 22 Plan_Product_Family__c records
// to its real division. "Other / POS / Reports" splits across ALM (69 records: POS - Reports,
// Consulting) and Market Intelligence (17 records: Book Sales, Instruct Counsel) in PROD --
// placed under ALM as the volume majority.
Map<String, List<String>> groupToFamilies = new Map<String, List<String>>{
    'ALM' => new List<String>{ 'Law.com / ALM', 'Other ALM', 'Other / POS / Reports' },
    'Events' => new List<String>{ 'Events - Delegate Ticket', 'Events - Other', 'Events - Sponsorship' },
    'Market Intelligence' => new List<String>{
        'Advertising', 'AllHires / Law Careers Net', 'Expert Insight (GxR / IP)', 'Legal Monitor',
        'Lexology Compete', 'Lexology In-Depth', 'Lexology Index', 'Lexology Insight',
        'Lexology Intelligence', 'Lexology Panoramic', 'Performance Data - GxR/IP'
    },
    'MBL Seminars' => new List<String>{ 'MBL Seminars' },
    'Practice Intelligence' => new List<String>{
        'Docket Navigator', 'Lexology Academic', 'Lexology PRO', 'Specialist Platforms'
    }
};

Map<String, Decimal> groupSortOrder = new Map<String, Decimal>{
    'ALM' => 1, 'Market Intelligence' => 2, 'Practice Intelligence' => 3,
    'Events' => 4, 'MBL Seminars' => 5
};

Map<String, Plan_Product_Group__c> existingGroups = new Map<String, Plan_Product_Group__c>();
for (Plan_Product_Group__c g : [SELECT Id, Name FROM Plan_Product_Group__c]) {
    existingGroups.put(g.Name, g);
}

List<Plan_Product_Group__c> groupsToInsert = new List<Plan_Product_Group__c>();
for (String groupName : groupToFamilies.keySet()) {
    if (!existingGroups.containsKey(groupName)) {
        groupsToInsert.add(new Plan_Product_Group__c(
            Name = groupName,
            Sort_Order__c = groupSortOrder.get(groupName),
            Active__c = true));
    }
}
if (!groupsToInsert.isEmpty()) {
    insert groupsToInsert;
    for (Plan_Product_Group__c g : groupsToInsert) {
        existingGroups.put(g.Name, g);
    }
}
System.debug('GROUPS_CREATED=' + groupsToInsert.size());

Map<String, Id> familyToGroupId = new Map<String, Id>();
for (String groupName : groupToFamilies.keySet()) {
    Id groupId = existingGroups.get(groupName).Id;
    for (String famName : groupToFamilies.get(groupName)) {
        familyToGroupId.put(famName, groupId);
    }
}

List<Plan_Product_Family__c> famsToUpdate = new List<Plan_Product_Family__c>();
Integer unmatched = 0;
for (Plan_Product_Family__c f : [SELECT Id, Name, Product_Group__c FROM Plan_Product_Family__c]) {
    Id targetGroupId = familyToGroupId.get(f.Name);
    if (targetGroupId == null) {
        unmatched++;
        System.debug('NO GROUP MAPPING FOR: ' + f.Name);
        continue;
    }
    if (f.Product_Group__c != targetGroupId) {
        famsToUpdate.add(new Plan_Product_Family__c(Id = f.Id, Product_Group__c = targetGroupId));
    }
}
if (!famsToUpdate.isEmpty()) {
    update famsToUpdate;
}
System.debug('FAMILIES_UPDATED=' + famsToUpdate.size() + ' UNMATCHED=' + unmatched);
