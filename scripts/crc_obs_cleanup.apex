delete [SELECT Id FROM Opportunity WHERE Name='CRCTEST Obs'];
delete [SELECT Id FROM Account WHERE Name='CRCTEST Obs Acc'];
delete [SELECT Id FROM Flow_Log__c WHERE Error_Description__c='SIMULATED FAULT for observability test'];
System.debug('CRCTEST: OBS cleanup done; opps='+[SELECT COUNT() FROM Opportunity WHERE Name LIKE 'CRCTEST%']);
