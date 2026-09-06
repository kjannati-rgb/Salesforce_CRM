/* Setup + base data for CRC tests. Commits data for later scenario runs. */
Id NB = [SELECT Id FROM RecordType WHERE SobjectType='Opportunity' AND DeveloperName='New_Business' LIMIT 1].Id;
Date CD = Date.today().addMonths(2);

Application_Settings__c s = Application_Settings__c.getInstance(UserInfo.getUserId());
if (s == null || s.SetupOwnerId != UserInfo.getUserId()) { s = new Application_Settings__c(SetupOwnerId = UserInfo.getUserId()); }
s.Disable_Validation_Rules__c = true;            // silence unrelated VRs for my user
s.Disable_Autolaunch_Lightning_Flow__c = false;  // our flow must run
upsert s;

delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM Contact WHERE LastName LIKE 'CRCTEST%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'CRCTEST%'];

Account accOk = new Account(Name='CRCTEST Acc OK', BillingStreet='1 High St', BillingCity='London', BillingCountry='United Kingdom');
Account accNoBill = new Account(Name='CRCTEST Acc NoBill');
insert new Account[]{accOk, accNoBill};

Contact conOk = new Contact(FirstName='Pat', LastName='CRCTEST Complete', AccountId=accOk.Id,
    Email='pat@example.com', Title='CFO', MailingStreet='1 High St', MailingCity='London');
Contact conInc = new Contact(FirstName='Sam', LastName='CRCTEST Incomplete', AccountId=accOk.Id);
insert new Contact[]{conOk, conInc};

Opportunity oComplete  = new Opportunity(Name='CRCTEST Complete',  AccountId=accOk.Id,     StageName='Identify', Probability=10, CloseDate=CD, RecordTypeId=NB);
Opportunity oIncomplete= new Opportunity(Name='CRCTEST Incomplete',AccountId=accOk.Id,     StageName='Identify', Probability=10, CloseDate=CD, RecordTypeId=NB);
Opportunity oNoRole    = new Opportunity(Name='CRCTEST NoRole',    AccountId=accOk.Id,     StageName='Identify', Probability=10, CloseDate=CD, RecordTypeId=NB);
Opportunity oNoBill    = new Opportunity(Name='CRCTEST NoBill',    AccountId=accNoBill.Id, StageName='Identify', Probability=10, CloseDate=CD, RecordTypeId=NB);
insert new Opportunity[]{oComplete, oIncomplete, oNoRole, oNoBill};

insert new OpportunityContactRole[]{
    new OpportunityContactRole(OpportunityId=oComplete.Id,   ContactId=conOk.Id,  IsPrimary=true, Role='Decision Maker'),
    new OpportunityContactRole(OpportunityId=oIncomplete.Id, ContactId=conInc.Id, IsPrimary=true, Role='Decision Maker'),
    new OpportunityContactRole(OpportunityId=oNoBill.Id,     ContactId=conOk.Id,  IsPrimary=true, Role='Decision Maker')
};
System.debug('CRCTEST: SETUP DONE. SOQL used='+Limits.getQueries());
