List<String> r = new List<String>();
String RT_FC='012Tm000000xaVhIAI'; String RT_NF='012Px000003AadBIAS';
Account a = new Account(Name='Consolidated Test Acct'); insert a;

// A) Newsfeed end-to-end: stamp Name + Campaign + membership (all via PFC_On_Save)
try {
  Contact c = new Contact(FirstName='Cara', LastName='Consol-A', AccountId=a.Id); insert c;
  insert new Task(Subject='NF - Cara Consol - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
  Pardot_Form_Completion__c p = [SELECT Name, Campaign__c, Campaign__r.Name, PFC_Source__c, Product_Brand__c FROM Pardot_Form_Completion__c WHERE Contact__c=:c.Id LIMIT 1];
  Integer m = [SELECT COUNT() FROM CampaignMember WHERE ContactId=:c.Id AND Campaign.Name='Lexology - Free Newsfeed Subscribers'];
  Boolean ok = p.Name.contains('Cara Consol-A') && p.Name.contains('Lexology Newsfeed Subscriber') && p.Campaign__r.Name=='Lexology - Free Newsfeed Subscribers' && p.PFC_Source__c=='Newsfeed' && m==1;
  r.add('A newsfeed (name+campaign+member): ' + (ok?'PASS':'FAIL name=['+p.Name+'] camp='+p.Campaign__r.Name+' src='+p.PFC_Source__c+' members='+m));
} catch(Exception e){ r.add('A ERROR '+e.getMessage()); }

// B) Cross-link forward: open inbound (Lexology) + NF -> newsfeed links to inbound
try {
  Contact c = new Contact(FirstName='Bo', LastName='Consol-B', AccountId=a.Id); insert c;
  Pardot_Form_Completion__c inb = new Pardot_Form_Completion__c(Name='B inbound', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='Working'); insert inb;
  insert new Task(Subject='NF - Bo Consol - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
  Pardot_Form_Completion__c nf = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Contact__c=:c.Id AND RecordTypeId=:RT_NF LIMIT 1];
  r.add('B cross-link NF->inbound: ' + (nf.Related_Form_Completion__c==inb.Id?'PASS':'FAIL got='+nf.Related_Form_Completion__c));
} catch(Exception e){ r.add('B ERROR '+e.getMessage()); }

// C) Inbound stamp: PFC: task -> Form Completion, Name stamped, source Inbound Form
try {
  Lead l = new Lead(FirstName='Dee', LastName='Consol-C', Company='Consol C Co'); insert l;
  insert new Task(Subject='PFC: GAR - LeadGen - Subscribe - Short Form', WhoId=l.Id, Status='Completed', Priority='Normal');
  Pardot_Form_Completion__c p = [SELECT Name, RecordType.DeveloperName, PFC_Source__c FROM Pardot_Form_Completion__c WHERE Lead__c=:l.Id LIMIT 1];
  Boolean ok = p.RecordType.DeveloperName=='Form_Completion' && p.PFC_Source__c=='Inbound Form' && p.Name!=null && p.Name.contains('GAR');
  r.add('C inbound stamp: ' + (ok?'PASS':'FAIL name=['+p.Name+'] rt='+p.RecordType.DeveloperName+' src='+p.PFC_Source__c));
} catch(Exception e){ r.add('C ERROR '+e.getMessage()); }

for (String s : r) System.debug('CONSOL ' + s);
