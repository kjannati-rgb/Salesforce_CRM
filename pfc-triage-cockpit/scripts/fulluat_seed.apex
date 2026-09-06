// FULLUAT UAT seed — ~10 records covering the UAT-SCRIPT scenarios.
// 1. Make sure MY automation is ON so the Task->orchestrator path fires.
List<Application_Settings__c> mine = [SELECT Id FROM Application_Settings__c WHERE SetupOwnerId = :UserInfo.getUserId()];
if (!mine.isEmpty()) { delete mine; }

Id caylaId = '005Tm000001WgWcIAK';
Id queueId = [SELECT Id FROM Group WHERE DeveloperName = 'PFC_Triage_Queue' AND Type = 'Queue' LIMIT 1].Id;
Id formRt = Schema.SObjectType.Pardot_Form_Completion__c.getRecordTypeInfosByDeveloperName().get('Form_Completion').getRecordTypeId();

// 2. Test leads + Tasks through the orchestrator (queue-owned, end-to-end)
List<Lead> leads = new List<Lead>();
for (Integer i = 1; i <= 3; i++) {
    leads.add(new Lead(FirstName = 'UAT' + i, LastName = 'Prospect' + i, Company = 'UAT Test Co ' + i,
        Email = 'uat' + i + '.prospect@uat-cockpit-test.example', Title = 'General Counsel',
        Country = 'United Kingdom'));
}
insert leads;
List<Task> tasks = new List<Task>();
for (Integer i = 0; i < 3; i++) {
    tasks.add(new Task(Subject = 'PFC: UAT Cockpit Form ' + (i + 1), Status = 'Completed',
        Priority = 'Normal', ActivityDate = Date.today(), WhoId = leads[i].Id));
}
insert tasks;

// 3. Real firm with active subscriptions -> realistic Account Context card
AggregateResult firmAgg = [SELECT Ultimate_Parent__c up, COUNT(Id) c FROM SBQQ__Subscription__c
    WHERE Ultimate_Parent__c != null AND SBQQ__StartDate__c <= TODAY AND SBQQ__EndDate__c >= TODAY
      AND SBQQ__TerminatedDate__c = null AND SBQQ__Bundled__c = false
    GROUP BY Ultimate_Parent__c ORDER BY COUNT(Id) DESC LIMIT 1];
Id firmId = (Id) firmAgg.get('up');
List<Contact> realCon = [SELECT Id, Name, Account.Name FROM Contact
    WHERE (AccountId = :firmId OR Account.Ultimate_Account__c = :firmId) AND Email != null LIMIT 1];
System.debug('SEED firm=' + firmId + ' subs=' + firmAgg.get('c') + ' contact=' + (realCon.isEmpty() ? 'NONE' : realCon[0].Name + ' @ ' + realCon[0].Account.Name));

List<Pardot_Form_Completion__c> direct = new List<Pardot_Form_Completion__c>();
if (!realCon.isEmpty()) {
    direct.add(new Pardot_Form_Completion__c(Name = 'UAT Contact-Linked', RecordTypeId = formRt,
        Sales_Stage__c = 'New', Contact__c = realCon[0].Id, Product_Brand__c = 'IAM',
        Form_Name__c = 'IAM - LeadGen - Subscribe - Short Form', PFC_Source__c = 'Inbound Form',
        OwnerId = caylaId));
}
// UTM + scored gauge record (Cayla-owned so it lands in her My Triage)
direct.add(new Pardot_Form_Completion__c(Name = 'UAT UTM Scored', RecordTypeId = formRt,
    Sales_Stage__c = 'New', Lead__c = leads[0].Id, Product_Brand__c = 'Lexology',
    Form_Name__c = 'Lexology - LeadGen - Lexology PRO Landing Page - Subscribe', PFC_Source__c = 'Inbound Form',
    UTM_Source__c = 'google', UTM_Medium__c = 'cpc', UTM_Campaign__c = 'lexpro-always-on',
    UTM_Term__c = 'legal know-how', UTM_Content__c = 'variant-a',
    Fit_Score__c = 83, Clay_Routed__c = true,
    Score_Reasoning__c = 'Senior in-house counsel; work areas match Lexology PRO ICP. (Simulated Clay output for UAT.)',
    OwnerId = caylaId));
// Overdue queue record (SLA sweep demo)
direct.add(new Pardot_Form_Completion__c(Name = 'UAT Overdue Queue', RecordTypeId = formRt,
    Sales_Stage__c = 'New', Lead__c = leads[1].Id, Product_Brand__c = 'GAR',
    Form_Name__c = 'GAR - LeadGen - Subscribe', PFC_Source__c = 'Inbound Form',
    OwnerId = queueId, Routing_Overdue__c = true));
// Disqualified example
List<Schema.PicklistEntry> reasons = Pardot_Form_Completion__c.Reason_Disqualified__c.getDescribe().getPicklistValues();
direct.add(new Pardot_Form_Completion__c(Name = 'UAT Disqualified', RecordTypeId = formRt,
    Sales_Stage__c = 'Disqualified', Lead__c = leads[2].Id, Product_Brand__c = 'WTR',
    Form_Name__c = 'WTR - LeadGen - Subscribe', PFC_Source__c = 'Inbound Form',
    Reason_Disqualified__c = reasons[0].getValue(), OwnerId = caylaId));
// Converted example linked to a real closed opp
List<Opportunity> realOpp = [SELECT Id FROM Opportunity WHERE IsClosed = true AND IsWon = true LIMIT 1];
if (!realOpp.isEmpty()) {
    direct.add(new Pardot_Form_Completion__c(Name = 'UAT Converted', RecordTypeId = formRt,
        Sales_Stage__c = 'Converted', Contact__c = (realCon.isEmpty() ? null : realCon[0].Id),
        Product_Brand__c = 'Lexology', Form_Name__c = 'Lexology - LeadGen - Lexology PRO - Subscribe',
        PFC_Source__c = 'Inbound Form', Opportunity__c = realOpp[0].Id, OwnerId = caylaId));
}
insert direct;

for (Pardot_Form_Completion__c p : [SELECT Id, Name, Owner.Name, Sales_Stage__c FROM Pardot_Form_Completion__c
        WHERE Id IN :direct OR (CreatedDate = TODAY AND Form_Name__c LIKE 'UAT Cockpit Form%')]) {
    System.debug('SEED ' + p.Name + ' | ' + p.Sales_Stage__c + ' | owner=' + p.Owner.Name + ' | ' + p.Id);
}
