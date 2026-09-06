// REV-57 relink verification: seed Lead + PFC, convert, confirm PFC moves Lead->Contact
Lead l = new Lead(FirstName='Relink', LastName='RelinkTest57', Company='REV57TestCo', Email='rev57relink@example.com');
insert l;
Pardot_Form_Completion__c pfc = new Pardot_Form_Completion__c(Name='REV57 Relink Test', Lead__c = l.Id, Sales_Stage__c = 'New');
insert pfc;
System.debug('SEED_BEFORE pfc=' + pfc.Id + ' lead=' + pfc.Lead__c + ' contact=' + pfc.Contact__c);

String convStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel;
Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId(l.Id);
lc.setConvertedStatus(convStatus);
lc.setDoNotCreateOpportunity(true);
Database.LeadConvertResult res = Database.convertLead(lc);
System.debug('CONVERT success=' + res.isSuccess() + ' contactId=' + res.getContactId());

Pardot_Form_Completion__c after = [SELECT Id, Lead__c, Contact__c FROM Pardot_Form_Completion__c WHERE Id = :pfc.Id];
System.debug('VERIFY_AFTER lead=' + after.Lead__c + ' contact=' + after.Contact__c + ' expectedContact=' + res.getContactId());
System.debug('RELINK_RESULT=' + ((after.Contact__c == res.getContactId() && after.Lead__c == null) ? 'PASS' : 'FAIL'));
