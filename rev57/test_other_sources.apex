List<String> r = new List<String>();
// EVT
Lead l1 = new Lead(FirstName='Ev', LastName='EventTest', Company='EvCo'); insert l1;
insert new Task(Subject='EVT: WIPL 2026 - Law.com S&E Promo - Click', WhoId=l1.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c pe = [SELECT RecordType.DeveloperName, PFC_Source__c, Form_Name__c, Lead__c, Sales_Stage__c FROM Pardot_Form_Completion__c WHERE Lead__c=:l1.Id LIMIT 1];
r.add('EVT: rt=' + pe.RecordType.DeveloperName + ' src=' + pe.PFC_Source__c + ' form=[' + pe.Form_Name__c + '] stage=' + pe.Sales_Stage__c);

// Lead scoring MQL
Lead l2 = new Lead(FirstName='Mq', LastName='MqlTest', Company='MqCo'); insert l2;
insert new Task(Subject='Lead scoring MQL: GAR - Subscribe Form', WhoId=l2.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c pm = [SELECT RecordType.DeveloperName, PFC_Source__c, Form_Name__c, Lead__c, Sales_Stage__c FROM Pardot_Form_Completion__c WHERE Lead__c=:l2.Id LIMIT 1];
r.add('MQL: rt=' + pm.RecordType.DeveloperName + ' src=' + pm.PFC_Source__c + ' form=[' + pm.Form_Name__c + '] stage=' + pm.Sales_Stage__c);

for (String s : r) System.debug('OTHERSRC ' + s);
