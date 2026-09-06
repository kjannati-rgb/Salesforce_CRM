Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST Incomplete' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Negotiate',Probability=75); System.debug('CRCTEST: T2 incomplete@75 => SAVED (UNEXPECTED)'); }
catch(Exception e){ System.debug('CRCTEST: T2 incomplete@75 => BLOCKED: '+e.getMessage()); }
