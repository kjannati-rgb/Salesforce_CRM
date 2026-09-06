Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST NoBill' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Negotiate',Probability=75); System.debug('CRCTEST: T4 nobill@75 => SAVED (UNEXPECTED)'); }
catch(Exception e){ System.debug('CRCTEST: T4 nobill@75 => BLOCKED: '+e.getMessage()); }
