// Gate C test records — six visibility scenarios for the cockpit page walkthrough
Id queueId = [SELECT Id FROM Group WHERE DeveloperName = 'PFC_Triage_Queue' AND Type = 'Queue' LIMIT 1].Id;

Account acc = new Account(Name = 'Gate C Test Firm LLP');
insert acc;
Contact con = new Contact(FirstName = 'Cara', LastName = 'ContactTest', AccountId = acc.Id, Email = 'cara.contact@gatectest.example', Title = 'General Counsel');
insert con;
Lead led = new Lead(FirstName = 'Larry', LastName = 'LeadTest', Company = 'Standalone Legal Co', Email = 'larry.lead@gatectest.example', Title = 'Partner');
insert led;

String stage0 = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1].MasterLabel;
Opportunity opp = new Opportunity(Name = 'Gate C Test Opp', AccountId = acc.Id, StageName = stage0, CloseDate = Date.today().addDays(30));
insert opp;

List<Schema.PicklistEntry> reasons = Pardot_Form_Completion__c.Reason_Disqualified__c.getDescribe().getPicklistValues();
Id newsfeedRt = Schema.SObjectType.Pardot_Form_Completion__c.getRecordTypeInfosByDeveloperName().get('Newsfeed_Subscribers').getRecordTypeId();
Id formRt = Schema.SObjectType.Pardot_Form_Completion__c.getRecordTypeInfosByDeveloperName().get('Form_Completion').getRecordTypeId();

List<Pardot_Form_Completion__c> pfcs = new List<Pardot_Form_Completion__c>{
    new Pardot_Form_Completion__c(Name = 'GATEC-1 Lead-linked', RecordTypeId = formRt, Sales_Stage__c = 'New',
        Lead__c = led.Id, OwnerId = queueId, Product_Brand__c = 'Lexology', Form_Name__c = 'Gate C Lead Form',
        PFC_Source__c = 'Inbound Form', Routing_Overdue__c = true),
    new Pardot_Form_Completion__c(Name = 'GATEC-2 Contact-linked', RecordTypeId = formRt, Sales_Stage__c = 'Working',
        Contact__c = con.Id, Product_Brand__c = 'Lexology', Form_Name__c = 'Gate C Contact Form',
        PFC_Source__c = 'Inbound Form', Next_Step__c = 'Follow-up call', Next_Contact_Date__c = Date.today().addDays(3),
        OwnerId = UserInfo.getUserId()),
    new Pardot_Form_Completion__c(Name = 'GATEC-3 UTM', RecordTypeId = formRt, Sales_Stage__c = 'New',
        Lead__c = led.Id, Form_Name__c = 'Gate C UTM Form', PFC_Source__c = 'Inbound Form',
        UTM_Source__c = 'google', UTM_Medium__c = 'cpc', UTM_Campaign__c = 'lexpro-q3', UTM_Term__c = 'legal research', UTM_Content__c = 'ad-variant-b',
        OwnerId = queueId),
    new Pardot_Form_Completion__c(Name = 'GATEC-4 Newsfeed', RecordTypeId = newsfeedRt, Sales_Stage__c = 'New',
        Contact__c = con.Id, PFC_Source__c = 'Newsfeed', Product_Brand__c = 'Lexology', OwnerId = queueId),
    new Pardot_Form_Completion__c(Name = 'GATEC-5 Disqualified', RecordTypeId = formRt, Sales_Stage__c = 'Disqualified',
        Lead__c = led.Id, Form_Name__c = 'Gate C DQ Form', PFC_Source__c = 'Inbound Form',
        Reason_Disqualified__c = reasons[0].getValue(), OwnerId = UserInfo.getUserId()),
    new Pardot_Form_Completion__c(Name = 'GATEC-6 Opp-linked', RecordTypeId = formRt, Sales_Stage__c = 'Converted',
        Contact__c = con.Id, Form_Name__c = 'Gate C Converted Form', PFC_Source__c = 'Inbound Form',
        Opportunity__c = opp.Id, OwnerId = UserInfo.getUserId())
};
insert pfcs;
for (Pardot_Form_Completion__c p : [SELECT Id, Name, Date_Completed__c, Account_Contact__c FROM Pardot_Form_Completion__c WHERE Id IN :pfcs]) {
    System.debug('GATEC ' + p.Name + ' -> ' + p.Id + ' dateCompleted=' + p.Date_Completed__c + ' acct=' + p.Account_Contact__c);
}
