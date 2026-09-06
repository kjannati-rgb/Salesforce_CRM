delete [SELECT Id FROM Contact WHERE LastName LIKE 'CRCTEST%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'CRCTEST%'];
System.debug('CRCTEST: CLEAN3 contacts/accounts deleted; acc remaining='+[SELECT COUNT() FROM Account WHERE Name LIKE 'CRCTEST%']);
