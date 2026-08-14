// Seed a demo Firm + Offices, then run LeadMatchSelectService live against several leads.
Id firmRt   = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

// Clean any prior demo run (idempotent)
delete [SELECT Id FROM Account WHERE Name LIKE 'Globex%(DEMO)'];

Account firm = new Account(Name='Globex Legal (DEMO)', RecordTypeId=firmRt, Match_Domain__c='globex-demo.com');
insert firm;

Account london = new Account(Name='Globex London (DEMO)', RecordTypeId=officeRt, Ultimate_Account__c=firm.Id,
    BillingCountryCode='GB', BillingCity='London', No_of_Won_Office_Opportunities__c=12, Val_of_Won_Office_Opportunities__c=400000, CFY_No_of_Won_Office_Opportunities__c=3);
Account manch = new Account(Name='Globex Manchester (DEMO)', RecordTypeId=officeRt, Ultimate_Account__c=firm.Id,
    BillingCountryCode='GB', BillingCity='Manchester', No_of_Won_Office_Opportunities__c=40, Val_of_Won_Office_Opportunities__c=1500000, CFY_No_of_Won_Office_Opportunities__c=11);
Account ny = new Account(Name='Globex New York (DEMO)', RecordTypeId=officeRt, Ultimate_Account__c=firm.Id,
    BillingCountryCode='US', BillingCity='New York', No_of_Won_Office_Opportunities__c=60, Val_of_Won_Office_Opportunities__c=3000000, CFY_No_of_Won_Office_Opportunities__c=20);
insert new List<Account>{ london, manch, ny };

System.debug('LMSS_DEMO Firm=' + firm.Id + ' London=' + london.Id + ' Manchester=' + manch.Id + ' NY=' + ny.Id);

// Cases: label | email | country | region | website
List<List<String>> cases = new List<List<String>>{
    new List<String>{'A: UK lead in London',          'alice@globex-demo.com','GB','London',    null},
    new List<String>{'B: UK lead in Manchester',      'bob@globex-demo.com',  'GB','Manchester',null},
    new List<String>{'C: free-mail + website, NY',    'carol@gmail.com',      'GB','New York',  'https://www.globex-demo.com/contact'},
    new List<String>{'D: unknown domain',             'dan@unknown-xyz.com',  'GB','London',    null}
};

for (List<String> cse : cases) {
    LeadMatchSelectService.Request r = new LeadMatchSelectService.Request();
    r.email = cse[1]; r.countryCode = cse[2]; r.region = cse[3]; r.website = cse[4];
    LeadMatchSelectService.Result res = LeadMatchSelectService.matchAndSelect(
        new List<LeadMatchSelectService.Request>{ r })[0];
    System.debug('LMSS_DEMO ===== ' + cse[0] + ' (' + cse[1] + ')');
    System.debug('LMSS_DEMO   tier=' + res.confidenceTier + ' | firm=' + res.resolvedFirmName
        + ' | recommend=' + res.recommendedOfficeName + ' | conflict=' + res.conflict
        + ' | existingCustomer=' + res.existingCustomer);
    System.debug('LMSS_DEMO   why: ' + res.matchEvidence);
    if (res.candidateOffices != null) {
        for (LeadMatchSelectService.CandidateOffice c : res.candidateOffices) {
            System.debug('LMSS_DEMO     - ' + c.name + ' [' + c.evidence + ']');
        }
    }
}
