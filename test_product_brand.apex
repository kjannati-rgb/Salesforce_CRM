List<String> r = new List<String>();
// A) Inbound: Product_Brand should now be stamped = Brand__c
try {
  Lead l = new Lead(FirstName='PB', LastName='InbTest', Company='PB Co'); insert l;
  insert new Task(Subject='PFC: Latin Lawyer - LeadGen - Subscribe - Marketing - Gated Content', WhoId=l.Id, Status='Completed', Priority='Normal');
  Pardot_Form_Completion__c p = [SELECT Product_Brand__c, Brand__c, RecordType.DeveloperName FROM Pardot_Form_Completion__c WHERE Lead__c=:l.Id LIMIT 1];
  r.add('A inbound: Product_Brand='+p.Product_Brand__c+' Brand='+p.Brand__c+' rt='+p.RecordType.DeveloperName+' => '+(p.Product_Brand__c=='Latin Lawyer' ? 'PASS':'FAIL'));
} catch(Exception e){ r.add('A ERROR '+e.getMessage()); }
// B) Newsfeed: Product_Brand should stay Lexology (not overwritten)
try {
  Account a = new Account(Name='PB NF Acct'); insert a;
  Contact c = new Contact(FirstName='PB', LastName='NFTest', AccountId=a.Id); insert c;
  insert new Task(Subject='NF - PB NF - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
  Pardot_Form_Completion__c p = [SELECT Product_Brand__c FROM Pardot_Form_Completion__c WHERE Contact__c=:c.Id AND RecordTypeId='012Px000003AadBIAS' LIMIT 1];
  r.add('B newsfeed: Product_Brand='+p.Product_Brand__c+' => '+(p.Product_Brand__c=='Lexology' ? 'PASS':'FAIL'));
} catch(Exception e){ r.add('B ERROR '+e.getMessage()); }
for (String s : r) System.debug('PB '+s);
