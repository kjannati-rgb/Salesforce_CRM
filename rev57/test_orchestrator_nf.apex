// REV-57 orchestrator NF-path test: NF Task -> orchestrator creates a Newsfeed PFC.
Account acct = new Account(Name='REV57 NF Acct'); insert acct;
Contact c = new Contact(LastName='REV57_NF_Sub', AccountId=acct.Id); insert c;
Task t = new Task(Subject='NF - Test Subscriber - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
insert t;
List<Pardot_Form_Completion__c> pfcs = [SELECT Id, RecordType.DeveloperName, PFC_Source__c, Product_Brand__c, Form_Name__c, Contact__c, Lead__c, Sales_Stage__c, Sales_Rep__c, Clay_Routed__c FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id];
System.debug('NF_TEST count=' + pfcs.size());
for (Pardot_Form_Completion__c p : pfcs) {
    System.debug('NF_TEST rt=' + p.RecordType.DeveloperName + ' src=' + p.PFC_Source__c + ' brand=' + p.Product_Brand__c
        + ' form=[' + p.Form_Name__c + '] contact=' + p.Contact__c + ' stage=' + p.Sales_Stage__c
        + ' salesRep=' + p.Sales_Rep__c + ' clay=' + p.Clay_Routed__c);
}
Boolean ok = pfcs.size()==1 && pfcs[0].RecordType.DeveloperName=='Newsfeed_Subscribers'
    && pfcs[0].PFC_Source__c=='Newsfeed' && pfcs[0].Product_Brand__c=='Lexology'
    && pfcs[0].Contact__c==c.Id && pfcs[0].Sales_Stage__c=='New' && pfcs[0].Clay_Routed__c==false
    && (pfcs[0].Form_Name__c==null || pfcs[0].Form_Name__c=='');
System.debug('NF_TEST RESULT=' + (ok ? 'PASS' : 'FAIL'));
