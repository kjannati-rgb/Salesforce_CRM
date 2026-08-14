// Seed demo data for all 5 Smart Convert scenarios. Idempotent.
Id firmRt   = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

delete [SELECT Id FROM Lead WHERE Company LIKE '%(SCDEMO)%' AND IsConverted=false];
delete [SELECT Id FROM Contact WHERE Email LIKE '%@cc-demo.com'];
delete [SELECT Id FROM Account WHERE Name LIKE '%(SCDEMO)%'];

// --- Firms
Account dentons = new Account(Name='Dentons (SCDEMO)', RecordTypeId=firmRt, Match_Domain__c='dentons-demo.com');
Account cc      = new Account(Name='Clifford Chance (SCDEMO)', RecordTypeId=firmRt, Match_Domain__c='cc-demo.com');
Account baker   = new Account(Name='Baker (SCDEMO)', RecordTypeId=firmRt, Match_Domain__c='baker-demo.com');
Account kpmgUk  = new Account(Name='KPMG UK (SCDEMO)', RecordTypeId=firmRt, Match_Domain__c='kpmg-demo.com');
Account kpmgAp  = new Account(Name='KPMG APAC (SCDEMO)', RecordTypeId=firmRt, Match_Domain__c='kpmg-demo.com');
insert new List<Account>{ dentons, cc, baker, kpmgUk, kpmgAp };

// --- Offices
Account ccLondon = new Account(Name='Clifford Chance LLP (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=cc.Id, BillingCountryCode='GB', BillingCity='London', No_of_Won_Office_Opportunities__c=31, Val_of_Won_Office_Opportunities__c=1700000);
List<Account> offices = new List<Account>{
  new Account(Name='Dentons UK and Middle East LLP (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=dentons.Id, BillingCountryCode='GB', BillingCity='London', No_of_Won_Office_Opportunities__c=24, Val_of_Won_Office_Opportunities__c=1240000),
  new Account(Name='Dentons US LLP (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=dentons.Id, BillingCountryCode='US', BillingCity='Washington', No_of_Won_Office_Opportunities__c=11, Val_of_Won_Office_Opportunities__c=540000),
  ccLondon,
  new Account(Name='Baker Manchester (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=baker.Id, BillingCountryCode='GB', BillingCity='Manchester', No_of_Won_Office_Opportunities__c=7, Val_of_Won_Office_Opportunities__c=310000),
  new Account(Name='Baker London (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=baker.Id, BillingCountryCode='GB', BillingCity='London', No_of_Won_Office_Opportunities__c=24, Val_of_Won_Office_Opportunities__c=1240000),
  new Account(Name='KPMG Law Asia Pacific Pte (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=kpmgAp.Id, BillingCountryCode='SG', BillingCity='Singapore', No_of_Won_Office_Opportunities__c=6, Val_of_Won_Office_Opportunities__c=210000),
  new Account(Name='KPMG LLP UK (SCDEMO)', RecordTypeId=officeRt, Ultimate_Account__c=kpmgUk.Id, BillingCountryCode='GB', BillingCity='London', No_of_Won_Office_Opportunities__c=18, Val_of_Won_Office_Opportunities__c=880000)
};
insert offices;

// --- Existing contact for the "link" scenario
insert new Contact(FirstName='Daniel', LastName='Okafor', Email='d.okafor@cc-demo.com', AccountId=ccLondon.Id);

// --- Leads, one per scenario
List<Lead> leads = new List<Lead>{
  new Lead(FirstName='James', LastName='Carter', Company='Dentons (SCDEMO)', Title='Senior Associate', Email='j.carter@dentons-demo.com', CountryCode='GB', City='London', Status='Open - Not Contacted'),
  new Lead(FirstName='Daniel', LastName='Okafor', Company='Clifford Chance (SCDEMO)', Title='Partner', Email='d.okafor@cc-demo.com', CountryCode='GB', City='London', Status='Open - Not Contacted'),
  new Lead(FirstName='Priya', LastName='Shah', Company='Baker (SCDEMO)', Title='Knowledge Lawyer', Email='p.shah@baker-demo.com', CountryCode='GB', City='Manchester', Status='Open - Not Contacted'),
  new Lead(FirstName='Mei', LastName='Lin', Company='KPMG (SCDEMO)', Title='Counsel', Email='m.lin@kpmg-demo.com', CountryCode='SG', City='Singapore', Status='Open - Not Contacted'),
  new Lead(FirstName='Sofia', LastName='Reyes', Company='Reyes IP (SCDEMO)', Title='IP Paralegal', Email='sofia@reyes-ip-demo.es', CountryCode='ES', City='Madrid', Status='Open - Not Contacted')
};
insert leads;

String base='/lightning/r/Lead/';
System.debug('SC ===== open these Leads (page: Lead - Smart Convert) =====');
String[] tags=new String[]{'EXACT/existing-customer','EXISTING-CONTACT link','CONFLICT location vs opps','AMBIGUOUS firm picker','NO-MATCH guided create'};
for (Integer i=0;i<leads.size();i++) System.debug('SC '+tags[i]+'  ->  '+base+leads[i].Id+'/view');
