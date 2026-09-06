Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST Incomplete' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Evaluate',Probability=50); System.debug('CRCTEST: T5 incomplete@50(exact) => SAVED (UNEXPECTED)'); }
catch(Exception e){ System.debug('CRCTEST: T5 incomplete@50(exact) => BLOCKED: '+e.getMessage()); }
