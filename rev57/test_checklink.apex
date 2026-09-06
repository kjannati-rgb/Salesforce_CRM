// REV-57 PFC_Check_And_Link verification. Insert pairs sequentially (separate DML = separate "forms").
String RT_FC = '012Tm000000xaVhIAI';
String RT_NF = '012Px000003AadBIAS';
List<String> r = new List<String>();
Account acct;
try { acct = new Account(Name='REV57 Test Acct'); insert acct; }
catch(Exception e){ System.debug('CHECKLINK_RESULT ACCT ERROR: '+e.getMessage()); }

// C1 forward link: both Product_Brand=Lexology, open -> B links to A
try {
  Contact c = new Contact(LastName='REV57_CL1', AccountId=acct.Id); insert c;
  Pardot_Form_Completion__c a = new Pardot_Form_Completion__c(Name='C1-A', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert a;
  Pardot_Form_Completion__c b = new Pardot_Form_Completion__c(Name='C1-B', RecordTypeId=RT_NF, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert b;
  Pardot_Form_Completion__c b2 = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Id=:b.Id];
  r.add('C1 forward-link (NF->inbound): ' + (b2.Related_Form_Completion__c==a.Id ? 'PASS' : 'FAIL got='+b2.Related_Form_Completion__c));
} catch(Exception e){ r.add('C1 ERROR: '+e.getMessage()); }

// C2 symmetry: A legacy (Form_Name drives Brand__c=Lexology, no Product_Brand), B newsfeed Product_Brand=Lexology
try {
  Contact c = new Contact(LastName='REV57_CL2', AccountId=acct.Id); insert c;
  Pardot_Form_Completion__c a = new Pardot_Form_Completion__c(Name='C2-A', RecordTypeId=RT_FC, Contact__c=c.Id, Form_Name__c='Lexology - LeadGen - Lexology PRO - Subscribe', Sales_Stage__c='New'); insert a;
  Pardot_Form_Completion__c b = new Pardot_Form_Completion__c(Name='C2-B', RecordTypeId=RT_NF, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert b;
  Pardot_Form_Completion__c b2 = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Id=:b.Id];
  r.add('C2 symmetry (legacy Brand fallback): ' + (b2.Related_Form_Completion__c==a.Id ? 'PASS' : 'FAIL got='+b2.Related_Form_Completion__c));
} catch(Exception e){ r.add('C2 ERROR: '+e.getMessage()); }

// C3 different brand -> no link
try {
  Contact c = new Contact(LastName='REV57_CL3', AccountId=acct.Id); insert c;
  Pardot_Form_Completion__c a = new Pardot_Form_Completion__c(Name='C3-A', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert a;
  Pardot_Form_Completion__c b = new Pardot_Form_Completion__c(Name='C3-B', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='GAR', Sales_Stage__c='New'); insert b;
  Pardot_Form_Completion__c b2 = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Id=:b.Id];
  r.add('C3 different-brand no-link: ' + (b2.Related_Form_Completion__c==null ? 'PASS' : 'FAIL got='+b2.Related_Form_Completion__c));
} catch(Exception e){ r.add('C3 ERROR: '+e.getMessage()); }

// C4 prior is closed (Disqualified) -> no link
try {
  Contact c = new Contact(LastName='REV57_CL4', AccountId=acct.Id); insert c;
  Pardot_Form_Completion__c a = new Pardot_Form_Completion__c(Name='C4-A', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='Disqualified', Reason_Disqualified__c='No response'); insert a;
  Pardot_Form_Completion__c b = new Pardot_Form_Completion__c(Name='C4-B', RecordTypeId=RT_NF, Contact__c=c.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert b;
  Pardot_Form_Completion__c b2 = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Id=:b.Id];
  r.add('C4 closed-stage no-link: ' + (b2.Related_Form_Completion__c==null ? 'PASS' : 'FAIL got='+b2.Related_Form_Completion__c));
} catch(Exception e){ r.add('C4 ERROR: '+e.getMessage()); }

// C5 brand=Other -> no link
try {
  Contact c = new Contact(LastName='REV57_CL5', AccountId=acct.Id); insert c;
  Pardot_Form_Completion__c a = new Pardot_Form_Completion__c(Name='C5-A', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Other', Sales_Stage__c='New'); insert a;
  Pardot_Form_Completion__c b = new Pardot_Form_Completion__c(Name='C5-B', RecordTypeId=RT_FC, Contact__c=c.Id, Product_Brand__c='Other', Sales_Stage__c='New'); insert b;
  Pardot_Form_Completion__c b2 = [SELECT Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Id=:b.Id];
  r.add('C5 Other-brand no-link: ' + (b2.Related_Form_Completion__c==null ? 'PASS' : 'FAIL got='+b2.Related_Form_Completion__c));
} catch(Exception e){ r.add('C5 ERROR: '+e.getMessage()); }

for(String s : r) System.debug('CHECKLINK_RESULT '+s);
