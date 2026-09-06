// Simulate Pardot creating the NF Task -> orchestrator should create the Newsfeed PFC.
Account a = new Account(Name='Maddox Legal LLP'); insert a;
Contact c = new Contact(FirstName='Jordan', LastName='Maddox', Email='jordan.maddox@maddoxlegal.com', AccountId=a.Id); insert c;

Task t = new Task(
    Subject = 'NF - Jordan Maddox - Lexology - Free Newsfeed Subscriber - June 2026',
    WhoId   = c.Id,
    Status  = 'Completed',
    Priority= 'Normal');
insert t;

List<Pardot_Form_Completion__c> p = [
    SELECT Id, Name, RecordType.DeveloperName, PFC_Source__c, Product_Brand__c, Form_Name__c, Brand__c,
           Contact__c, Lead__c, Sales_Stage__c, Sales_Rep__c, Clay_Routed__c, Related_Form_Completion__c
    FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id];

System.debug('NFLIVE TASK_ID=' + t.Id + ' CONTACT_ID=' + c.Id);
System.debug('NFLIVE PFC_COUNT=' + p.size());
for (Pardot_Form_Completion__c x : p) {
    System.debug('NFLIVE PFC_ID=' + x.Id);
    System.debug('NFLIVE FIELDS rt=' + x.RecordType.DeveloperName + ' | source=' + x.PFC_Source__c
        + ' | productBrand=' + x.Product_Brand__c + ' | brandFormula=' + x.Brand__c
        + ' | formName=[' + x.Form_Name__c + '] | contact=' + x.Contact__c + ' | lead=' + x.Lead__c
        + ' | stage=' + x.Sales_Stage__c + ' | salesRep=' + x.Sales_Rep__c
        + ' | clayRouted=' + x.Clay_Routed__c + ' | relatedFormCompletion=' + x.Related_Form_Completion__c);
}
