Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST Complete' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Evaluate',Probability=50); System.debug('CRCTEST: T7 complete@50(exact) => SAVED'); }
catch(Exception e){ System.debug('CRCTEST: T7 complete@50(exact) => BLOCKED (UNEXPECTED): '+e.getMessage()); }
