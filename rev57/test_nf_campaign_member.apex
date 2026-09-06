Account a = new Account(Name='Newsfeed Camp Test Acct'); insert a;
Contact c = new Contact(FirstName='Nadia', LastName='Newsfeed', Email='nadia@example.com', AccountId=a.Id); insert c;
insert new Task(Subject='NF - Nadia Newsfeed - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');

Pardot_Form_Completion__c p = [SELECT Id, Campaign__c, Campaign__r.Name, Contact__c FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id LIMIT 1];
System.debug('NFCM PFC_ID=' + p.Id + ' Campaign=' + p.Campaign__c + ' CampaignName=[' + p.Campaign__r.Name + ']');

List<CampaignMember> cms = [SELECT Id, CampaignId, Campaign.Name, ContactId, Status FROM CampaignMember WHERE ContactId = :c.Id];
System.debug('NFCM member_count=' + cms.size());
for (CampaignMember m : cms) System.debug('NFCM member campaign=[' + m.Campaign.Name + '] status=' + m.Status);
System.debug('NFCM RESULT=' + (p.Campaign__r.Name=='Lexology - Free Newsfeed Subscribers' && cms.size()==1 && cms[0].Status=='Registered' ? 'PASS' : 'FAIL'));
