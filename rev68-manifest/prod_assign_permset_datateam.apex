// REV-68: assign LBR_Interactions_on_Leads to active users on the data team profile.
Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'LBR_Interactions_on_Leads' LIMIT 1].Id;
Set<Id> already = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :psId]) {
    already.add(a.AssigneeId);
}
List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
for (User u : [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'Custom: Data Management']) {
    if (!already.contains(u.Id)) toAdd.add(new PermissionSetAssignment(PermissionSetId = psId, AssigneeId = u.Id));
}
Database.SaveResult[] srs = Database.insert(toAdd, false);
Integer ok = 0, fail = 0;
for (Database.SaveResult sr : srs) { if (sr.isSuccess()) ok++; else fail++; }
System.debug('REV68_ASSIGN_DATA attempted=' + toAdd.size() + ' ok=' + ok + ' fail=' + fail);
