delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'CRCTEST%'];
System.debug('CRCTEST: cleanup2 opps='+[SELECT COUNT() FROM Opportunity WHERE Name LIKE 'CRCTEST%']+' accts='+[SELECT COUNT() FROM Account WHERE Name LIKE 'CRCTEST%']);
