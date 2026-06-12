// REV-71 sync test 1c: re-prime the test quote (transaction 2 of toggle) — CPQ
// primary-quote sync should now create OLIs for all quote lines.
SBQQ__Quote__c q = [
    SELECT Id, SBQQ__Primary__c FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
    LIMIT 1
];
q.SBQQ__Primary__c = true;
update q;
System.debug('REV71_REPRIME quote=' + q.Id);
