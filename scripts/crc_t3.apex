Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST NoRole' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Negotiate',Probability=75); System.debug('CRCTEST: T3 norole@75 => SAVED (UNEXPECTED)'); }
catch(Exception e){ System.debug('CRCTEST: T3 norole@75 => BLOCKED: '+e.getMessage()); }
