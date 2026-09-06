Account a = new Account(Name='Cimcorp Demo'); insert a;
Contact c = new Contact(FirstName='Mika', LastName='Martikainen', Email='mika.martikainen@cimcorp.com', AccountId=a.Id); insert c;
insert new Task(Subject='NF - Mika Martikainen - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c p = [SELECT Id, Name, Form_Name__c, Brand__c, Product_Brand__c, PFC_Source__c, Prospect_Name__c, Company__c, Email__c, Sales_Stage__c
    FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id LIMIT 1];
System.debug('NFNAME PFC_ID=' + p.Id);
System.debug('NFNAME Name=[' + p.Name + ']');
System.debug('NFNAME FormName=[' + p.Form_Name__c + '] Brand=' + p.Brand__c + ' ProductBrand=' + p.Product_Brand__c + ' Source=' + p.PFC_Source__c);
System.debug('NFNAME ProspectName=[' + p.Prospect_Name__c + '] Company=[' + p.Company__c + '] Email=[' + p.Email__c + ']');
