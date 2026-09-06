// REV-68: assign LBR_Interactions_on_Leads to active users on Non-ALM sales/admin profiles.
Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'LBR_Interactions_on_Leads' LIMIT 1].Id;
Set<Id> already = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :psId]) {
    already.add(a.AssigneeId);
}
List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
for (User u : [SELECT Id FROM User
               WHERE IsActive = true
               AND Profile.Name IN ('Custom: Sales Profile', 'Custom: Sales Admin', 'System Administrator')]) {
    if (!already.contains(u.Id)) toAdd.add(new PermissionSetAssignment(PermissionSetId = psId, AssigneeId = u.Id));
}
List<Database.SaveResult> srs = Database.insert(toAdd, false);
Integer ok = 0, fail = 0; String firstErr = '';
for (Database.SaveResult sr : srs) {
    if (sr.isSuccess()) ok++; else { fail++; if (firstErr == '') firstErr = sr.getErrors()[0].getMessage(); }
}
System.debug('REV68_ASSIGN attempted=' + toAdd.size() + ' ok=' + ok + ' fail=' + fail + ' firstErr=' + firstErr);
