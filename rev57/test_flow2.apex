// Flow-2 Campaign config fix verification
String RT_FC = '012Tm000000xaVhIAI';
Account a = new Account(Name='F2 Test Acct'); insert a;

// Phase 1: campaign does NOT exist in KJDEV -> must NOT error (was INSUFFICIENT_ACCESS before), Campaign stays null
Contact c1 = new Contact(LastName='F2NoCamp', AccountId=a.Id); insert c1;
Pardot_Form_Completion__c p1 = new Pardot_Form_Completion__c(Name='F2-nocamp', RecordTypeId=RT_FC, Form_Name__c='Lexology - LeadGen - Lexology PRO - Subscribe', Sales_Stage__c='New'); insert p1;
String r1;
try {
    p1.Contact__c = c1.Id; update p1;
    Pardot_Form_Completion__c af = [SELECT Campaign__c FROM Pardot_Form_Completion__c WHERE Id = :p1.Id];
    r1 = 'F2_NOCAMP (expect no error, Campaign null): ' + (af.Campaign__c==null ? 'PASS' : 'FAIL camp='+af.Campaign__c);
} catch(Exception e){ r1 = 'F2_NOCAMP: FAIL ' + e.getMessage(); }
System.debug('F2_RESULT ' + r1);

// Phase 2: create the campaign by name -> lookup resolves Campaign Id
Campaign camp = new Campaign(Name='Lexology - LeadGen Form - ROI Campaign', IsActive=true, Type='Other'); insert camp;
Contact c2 = new Contact(LastName='F2WithCamp', AccountId=a.Id); insert c2;
Pardot_Form_Completion__c p2 = new Pardot_Form_Completion__c(Name='F2-withcamp', RecordTypeId=RT_FC, Form_Name__c='Lexology - LeadGen - Lexology PRO - Subscribe', Sales_Stage__c='New'); insert p2;
String r2;
try {
    p2.Contact__c = c2.Id; update p2;
    Pardot_Form_Completion__c af = [SELECT Campaign__c FROM Pardot_Form_Completion__c WHERE Id = :p2.Id];
    r2 = 'F2_WITHCAMP (expect resolves to camp): ' + (af.Campaign__c==camp.Id ? 'PASS' : 'FAIL got='+af.Campaign__c+' expect='+camp.Id);
} catch(Exception e){ r2 = 'F2_WITHCAMP: FAIL ' + e.getMessage(); }
System.debug('F2_RESULT ' + r2);

// Phase 3: unmapped form name -> Campaign null, no error
Contact c3 = new Contact(LastName='F2Unmapped', AccountId=a.Id); insert c3;
Pardot_Form_Completion__c p3 = new Pardot_Form_Completion__c(Name='F2-unmapped', RecordTypeId=RT_FC, Form_Name__c='GAR - LeadGen - Subscribe - Short Form', Sales_Stage__c='New'); insert p3;
String r3;
try {
    p3.Contact__c = c3.Id; update p3;
    Pardot_Form_Completion__c af = [SELECT Campaign__c FROM Pardot_Form_Completion__c WHERE Id = :p3.Id];
    r3 = 'F2_UNMAPPED (expect Campaign null): ' + (af.Campaign__c==null ? 'PASS' : 'FAIL camp='+af.Campaign__c);
} catch(Exception e){ r3 = 'F2_UNMAPPED: FAIL ' + e.getMessage(); }
System.debug('F2_RESULT ' + r3);
