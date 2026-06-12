// REV-71: mirror FLS from OpportunityLineItem.Full_Contract_Value__c onto the new
// SBQQ__QuoteLine__c.Full_Contract_Value__c twin field. Idempotent: skips parents
// that already have a FieldPermissions row for the twin. allOrNone=false so parents
// that cannot accept the grant (e.g. no object perms) are reported, not fatal.
List<FieldPermissions> src = [
    SELECT ParentId, PermissionsRead, PermissionsEdit
    FROM FieldPermissions
    WHERE SobjectType = 'OpportunityLineItem'
      AND Field = 'OpportunityLineItem.Full_Contract_Value__c'
];
Set<Id> existing = new Set<Id>();
for (FieldPermissions fp : [
    SELECT ParentId FROM FieldPermissions
    WHERE SobjectType = 'SBQQ__QuoteLine__c'
      AND Field = 'SBQQ__QuoteLine__c.Full_Contract_Value__c'
]) {
    existing.add(fp.ParentId);
}
List<FieldPermissions> toInsert = new List<FieldPermissions>();
for (FieldPermissions s : src) {
    if (existing.contains(s.ParentId)) continue;
    toInsert.add(new FieldPermissions(
        ParentId = s.ParentId,
        SobjectType = 'SBQQ__QuoteLine__c',
        Field = 'SBQQ__QuoteLine__c.Full_Contract_Value__c',
        PermissionsRead = s.PermissionsRead,
        PermissionsEdit = s.PermissionsEdit
    ));
}
Database.SaveResult[] results = Database.insert(toInsert, false);
Integer ok = 0;
List<String> errs = new List<String>();
for (Integer i = 0; i < results.size(); i++) {
    if (results[i].isSuccess()) {
        ok++;
    } else {
        errs.add(toInsert[i].ParentId + ': ' + results[i].getErrors()[0].getMessage());
    }
}
System.debug('REV71_FLS source=' + src.size() + ' attempted=' + toInsert.size() + ' inserted=' + ok + ' errors=' + errs.size());
for (String e : errs) System.debug('REV71_FLS_ERR ' + e);
