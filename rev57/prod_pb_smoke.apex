Lead l = new Lead(FirstName='PBProd', LastName='Smoke Test', Company='PBProd Co'); insert l;
insert new Task(Subject='PFC: Latin Lawyer - LeadGen - Subscribe - Marketing - Gated Content', WhoId=l.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c p = [SELECT Product_Brand__c, Brand__c FROM Pardot_Form_Completion__c WHERE Lead__c=:l.Id LIMIT 1];
System.debug('PBPROD Product_Brand='+p.Product_Brand__c+' Brand='+p.Brand__c+' => '+(p.Product_Brand__c=='Latin Lawyer'?'PASS':'FAIL'));
delete p; delete [SELECT Id FROM Task WHERE WhoId=:l.Id]; delete l;
