/**
 * Centellic Payment Term Extension Process - FLS mirroring (idempotent, org-agnostic)
 * Run via: sf apex run --file scripts/payment_terms_fls.apex -o <orgAlias>
 *
 * - ACV_GBP__c + Payment_Terms_Days__c (formulas): read granted to every permission-set/
 *   profile parent that can read Net_Amount_GBP__c.
 * - Payment_Terms_Justification__c: read+edit mirrored from SBQQ__PaymentTerms__c
 *   (whoever can edit payment terms must be able to justify them).
 */
String obj = 'SBQQ__Quote__c';

Map<String, List<FieldPermissions>> byField = new Map<String, List<FieldPermissions>>{
    'SBQQ__Quote__c.Net_Amount_GBP__c' => new List<FieldPermissions>(),
    'SBQQ__Quote__c.SBQQ__PaymentTerms__c' => new List<FieldPermissions>()
};
for (FieldPermissions fp : [SELECT ParentId, Field, PermissionsRead, PermissionsEdit
                            FROM FieldPermissions
                            WHERE SobjectType = :obj AND Field IN :byField.keySet()]) {
    byField.get(fp.Field).add(fp);
}

Set<String> existingNew = new Set<String>();
for (FieldPermissions fp : [SELECT ParentId, Field FROM FieldPermissions
                            WHERE SobjectType = :obj
                              AND Field IN ('SBQQ__Quote__c.ACV_GBP__c',
                                            'SBQQ__Quote__c.Payment_Terms_Days__c',
                                            'SBQQ__Quote__c.Payment_Terms_Justification__c')]) {
    existingNew.add(fp.ParentId + ':' + fp.Field);
}

List<FieldPermissions> toInsert = new List<FieldPermissions>();
for (FieldPermissions src : byField.get('SBQQ__Quote__c.Net_Amount_GBP__c')) {
    if (!src.PermissionsRead) continue;
    for (String f : new List<String>{'SBQQ__Quote__c.ACV_GBP__c', 'SBQQ__Quote__c.Payment_Terms_Days__c'}) {
        if (!existingNew.contains(src.ParentId + ':' + f)) {
            toInsert.add(new FieldPermissions(ParentId = src.ParentId, SobjectType = obj,
                Field = f, PermissionsRead = true, PermissionsEdit = false));
        }
    }
}
for (FieldPermissions src : byField.get('SBQQ__Quote__c.SBQQ__PaymentTerms__c')) {
    if (!src.PermissionsRead) continue;
    String f = 'SBQQ__Quote__c.Payment_Terms_Justification__c';
    if (!existingNew.contains(src.ParentId + ':' + f)) {
        toInsert.add(new FieldPermissions(ParentId = src.ParentId, SobjectType = obj,
            Field = f, PermissionsRead = true, PermissionsEdit = src.PermissionsEdit));
    }
}

Database.SaveResult[] results = Database.insert(toInsert, false);
Integer ok = 0; Integer fail = 0;
for (Database.SaveResult r : results) {
    if (r.isSuccess()) { ok++; } else { fail++; System.debug('FLS insert failed: ' + r.getErrors()[0].getMessage()); }
}
System.debug('FLS mirror complete. Inserted: ' + ok + ' | Failed: ' + fail + ' | Attempted: ' + toInsert.size());
