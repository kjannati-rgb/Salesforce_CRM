Account a = new Account(Name='Cimcorp Demo 2'); insert a;
Contact c = new Contact(FirstName='Mika', LastName='Martikainen', Email='mika.martikainen@cimcorp.com', AccountId=a.Id); insert c;
insert new Task(Subject='NF - Mika Martikainen - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c p = [SELECT Id, Name, Form_Name__c, Brand__c, Product_Brand__c, PFC_Source__c
    FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id LIMIT 1];
System.debug('NFN2 PFC_ID=' + p.Id);
System.debug('NFN2 Name=[' + p.Name + ']');
System.debug('NFN2 FormName=[' + p.Form_Name__c + '] Brand=' + p.Brand__c + ' ProductBrand=' + p.Product_Brand__c + ' Source=' + p.PFC_Source__c);
