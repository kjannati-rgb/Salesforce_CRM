List<String> r = new List<String>();
// A) INBOUND stamp via PFC_On_Save: PFC: task -> Form Completion, Name stamped, Lead linked
try {
    Lead l = new Lead(FirstName='REV77', LastName='Consol Smoke Inbound', Company='REV77 Smoke Co'); insert l;
    insert new Task(Subject='PFC: GAR - LeadGen - Subscribe - Short Form', WhoId=l.Id, Status='Completed', Priority='Normal');
    Pardot_Form_Completion__c p = [SELECT Id, Name, RecordType.DeveloperName, Lead__c FROM Pardot_Form_Completion__c WHERE Lead__c=:l.Id LIMIT 1];
    Boolean ok = p.RecordType.DeveloperName=='Form_Completion' && p.Lead__c==l.Id && p.Name!=null && p.Name.contains('GAR') && p.Name.contains('Consol Smoke Inbound');
    r.add('A inbound stamp: ' + (ok?'PASS':'FAIL name=['+p.Name+'] rt='+p.RecordType.DeveloperName));
    delete p; delete [SELECT Id FROM Task WHERE WhoId=:l.Id]; delete l;
} catch(Exception e){ r.add('A ERROR '+e.getMessage()); }

// B) NEWSFEED via PFC_On_Save: name + campaign + Registered member
try {
    Account a = new Account(Name='REV77 Consol Smoke Acct'); insert a;
    Contact c = new Contact(FirstName='REV77', LastName='Consol Smoke NF', AccountId=a.Id); insert c;
    insert new Task(Subject='NF - REV77 Consol Smoke - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
    Pardot_Form_Completion__c p = [SELECT Id, Name, Campaign__r.Name FROM Pardot_Form_Completion__c WHERE Contact__c=:c.Id LIMIT 1];
    Integer m = [SELECT COUNT() FROM CampaignMember WHERE ContactId=:c.Id AND Campaign.Name='Lexology - Free Newsfeed Subscribers'];
    Boolean ok = p.Name!=null && p.Name.contains('Lexology Newsfeed Subscriber') && p.Campaign__r.Name=='Lexology - Free Newsfeed Subscribers' && m==1;
    r.add('B newsfeed name+campaign+member: ' + (ok?'PASS':'FAIL name=['+p.Name+'] camp='+p.Campaign__r.Name+' members='+m));
    delete [SELECT Id FROM CampaignMember WHERE ContactId=:c.Id]; delete p; delete [SELECT Id FROM Task WHERE WhoId=:c.Id]; delete c; delete a;
} catch(Exception e){ r.add('B ERROR '+e.getMessage()); }

for (String s : r) System.debug('PRODCONSOL ' + s);
