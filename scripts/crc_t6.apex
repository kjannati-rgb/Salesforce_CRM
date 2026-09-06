Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST Incomplete' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Qualify',Probability=49); 
 Opportunity r=[SELECT Has_Contact_Role__c,Has_Complete_Contact_Role__c FROM Opportunity WHERE Id=:i];
 System.debug('CRCTEST: T6 incomplete@49 => SAVED. HasRole='+r.Has_Contact_Role__c+' Complete='+r.Has_Complete_Contact_Role__c); }
catch(Exception e){ System.debug('CRCTEST: T6 incomplete@49 => BLOCKED (UNEXPECTED): '+e.getMessage()); }
