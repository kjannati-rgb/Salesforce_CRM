List<Flow_Log__c> logs=[SELECT Id FROM Flow_Log__c WHERE Record_Name__c='CRCTEST Obs'];
delete logs;
System.debug('CRCTEST: deleted test flow logs='+logs.size());
