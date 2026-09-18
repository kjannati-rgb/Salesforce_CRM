// Mirror FLS: Opportunity.Solutions_Engineer__c gets exactly the same read/edit grants as
// Opportunity.Sales_Development_Representative__c (profiles + permission sets). Idempotent.
String src = 'Opportunity.Sales_Development_Representative__c';
String dst = 'Opportunity.Solutions_Engineer__c';
Set<Id> already = new Set<Id>();
for (FieldPermissions f : [SELECT ParentId FROM FieldPermissions WHERE Field = :dst AND SobjectType = 'Opportunity']) already.add(f.ParentId);
List<FieldPermissions> toAdd = new List<FieldPermissions>();
for (FieldPermissions f : [SELECT ParentId, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE Field = :src AND SobjectType = 'Opportunity']) {
    if (already.contains(f.ParentId)) continue;
    toAdd.add(new FieldPermissions(ParentId = f.ParentId, SobjectType = 'Opportunity', Field = dst,
                                   PermissionsRead = f.PermissionsRead, PermissionsEdit = f.PermissionsEdit));
}
Integer ok = 0, fail = 0;
for (Database.SaveResult r : Database.insert(toAdd, false)) {
    if (r.isSuccess()) ok++; else { fail++; System.debug('FLS_FAIL ' + r.getErrors()[0].getMessage()); }
}
System.debug('FLS_MIRROR planned=' + toAdd.size() + ' ok=' + ok + ' fail=' + fail + ' alreadyHad=' + already.size());
