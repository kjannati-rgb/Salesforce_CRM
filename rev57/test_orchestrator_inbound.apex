// REV-57 orchestrator INBOUND regression: PFC: Task (Lead) -> Form_Completion PFC, mirrors flow 1 + adds source.
Lead l = new Lead(FirstName='Inb', LastName='REV57_Inbound', Company='REV57TestCo'); insert l;
// Use a GAR form name: flow 2's Campaign CASE doesn't map it, avoiding the KJDEV hardcoded-Campaign cross-ref gap.
Task t = new Task(Subject='PFC: GAR - LeadGen - Subscribe - Short Form', WhoId=l.Id, Status='Completed', Priority='Normal');
insert t;
List<Pardot_Form_Completion__c> pfcs = [SELECT Id, RecordType.DeveloperName, PFC_Source__c, Product_Brand__c, Form_Name__c, Brand__c, Lead__c, Contact__c, Sales_Stage__c, Sales_Rep__c FROM Pardot_Form_Completion__c WHERE Lead__c = :l.Id];
System.debug('INB count=' + pfcs.size());
for (Pardot_Form_Completion__c p : pfcs) {
    System.debug('INB rt=' + p.RecordType.DeveloperName + ' src=' + p.PFC_Source__c + ' prodBrand=' + p.Product_Brand__c
        + ' brandFormula=' + p.Brand__c + ' form=[' + p.Form_Name__c + '] lead=' + p.Lead__c
        + ' stage=' + p.Sales_Stage__c + ' salesRep=' + p.Sales_Rep__c);
}
Boolean ok = pfcs.size()==1 && pfcs[0].RecordType.DeveloperName=='Form_Completion'
    && pfcs[0].PFC_Source__c=='Inbound Form' && pfcs[0].Lead__c==l.Id
    && pfcs[0].Sales_Stage__c=='New' && pfcs[0].Form_Name__c!=null
    && pfcs[0].Form_Name__c.contains('GAR') && pfcs[0].Brand__c=='GAR';
System.debug('INB RESULT=' + (ok ? 'PASS' : 'FAIL'));
