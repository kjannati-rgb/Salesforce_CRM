// REV-71 sync test 1b: take the test quote off primary (transaction 1 of toggle)
SBQQ__Quote__c q = [
    SELECT Id, SBQQ__Primary__c FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
    LIMIT 1
];
q.SBQQ__Primary__c = false;
update q;
System.debug('REV71_UNPRIME quote=' + q.Id);
