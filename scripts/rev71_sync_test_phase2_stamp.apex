// REV-71 — Step 2 sync verification, PHASE 2: stamp the twin field on the quote
// lines of the ZZ REV71-SYNC-01 quote and let CPQ re-sync. Run only after phase 1
// OLI creation is confirmed. Simulates what QL_ALM_Code_AfterSave will do.

SBQQ__Quote__c q = [
    SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
      AND SBQQ__Primary__c = true
    LIMIT 1
];
List<SBQQ__QuoteLine__c> qls = [
    SELECT Id, Full_Contract_Value__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :q.Id
];
for (SBQQ__QuoteLine__c ql : qls) {
    ql.Full_Contract_Value__c = 1;
}
update qls;
System.debug('REV71_STAMP quote=' + q.Id + ' lines=' + qls.size() + ' value=1');
