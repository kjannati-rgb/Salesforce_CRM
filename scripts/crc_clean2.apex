// delete opps in a small batch (run repeatedly); OCRs cascade-delete with the opp
Opportunity[] d=[SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST%' LIMIT 15];
Database.delete(d,false);
Integer remaining=[SELECT COUNT() FROM Opportunity WHERE Name LIKE 'CRCTEST%'];
System.debug('CRCTEST: CLEAN2 deleted='+d.size()+' remaining='+remaining);
