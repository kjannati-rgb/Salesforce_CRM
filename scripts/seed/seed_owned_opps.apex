/*
 * Seed representative "owned" entitlements (won Opportunities + line items) on the Globex offices so
 * WhitespaceGenerationService (§4) has real CRM ownership to generate the matrix from. Mirrors the
 * curated owned distribution. User-level automation bypass (Application_Settings__c) so it doesn't
 * affect other users. Re-runnable. Run AFTER the module + WhitespaceGenerationService are deployed.
 *   sf apex run --file scripts/seed/seed_owned_opps.apex --target-org KJDEV
 */

// 1) User-level automation bypass (this user only)
List<Application_Settings__c> ex = [SELECT Id FROM Application_Settings__c WHERE SetupOwnerId = :UserInfo.getUserId()];
Application_Settings__c bp = ex.isEmpty() ? new Application_Settings__c(SetupOwnerId = UserInfo.getUserId()) : ex[0];
bp.Disable_Validation_Rules__c = true;
bp.Disable_Process_Builders__c = true;
bp.Disable_Autolaunch_Lightning_Flow__c = true;
bp.Disable_Triggers__c = true;
upsert bp;

List<String> famNames = new List<String>{
    'Lexology PRO','Specialist Platforms','Lexology Intelligence','ALM Subs / IS','Events & Sponsorship','Advertising'};

// 2) Products (named = family) + standard pricebook entries
Map<String, Id> prodByName = new Map<String, Id>();
for (Product2 p : [SELECT Id, Name FROM Product2 WHERE Name IN :famNames]) prodByName.put(p.Name, p.Id);
List<Product2> newProds = new List<Product2>();
for (String n : famNames) if (!prodByName.containsKey(n)) newProds.add(new Product2(Name = n, IsActive = true, Reporting_Stream__c = 'Advertising - GAR'));
if (!newProds.isEmpty()) { insert newProds; for (Product2 p : newProds) prodByName.put(p.Name, p.Id); }

Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Map<String, Id> pbeByName = new Map<String, Id>();
for (PricebookEntry e : [SELECT Id, Product2.Name FROM PricebookEntry WHERE Pricebook2Id = :stdPb AND Product2.Name IN :famNames]) pbeByName.put(e.Product2.Name, e.Id);
List<PricebookEntry> newPbes = new List<PricebookEntry>();
for (String n : famNames) if (!pbeByName.containsKey(n)) newPbes.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = prodByName.get(n), UnitPrice = 1, IsActive = true));
if (!newPbes.isEmpty()) insert newPbes;
pbeByName = new Map<String, Id>();
for (PricebookEntry e : [SELECT Id, Product2.Name FROM PricebookEntry WHERE Pricebook2Id = :stdPb AND Product2.Name IN :famNames]) pbeByName.put(e.Product2.Name, e.Id);

// 3) Family mapping (so generation resolves product -> family explicitly)
List<Plan_Product_Family__c> fams = [SELECT Id, Name, CPQ_Family_Mapping__c FROM Plan_Product_Family__c WHERE Name IN :famNames];
for (Plan_Product_Family__c f : fams) f.CPQ_Family_Mapping__c = f.Name;
update fams;

// 4) Offices + owned distribution (city -> 'Family:ARR')
Map<String, Id> office = new Map<String, Id>();
for (Account a : [SELECT Id, BillingCity FROM Account WHERE Ultimate_Account__r.Name = 'Globex Legal (DEMO)' AND BillingCity != null]) office.put(a.BillingCity, a.Id);

Map<String, List<String>> owned = new Map<String, List<String>>{
    'London'     => new List<String>{ 'Lexology PRO:186000','Specialist Platforms:94000','ALM Subs / IS:72000','Events & Sponsorship:28000' },
    'Manchester' => new List<String>{ 'Lexology PRO:88000','Events & Sponsorship:12000' },
    'New York'   => new List<String>{ 'Lexology PRO:61000' }
};

delete [SELECT Id FROM Opportunity WHERE Name LIKE 'WS Owned - %'];
List<Opportunity> opps = new List<Opportunity>();
for (String city : owned.keySet()) {
    opps.add(new Opportunity(Name = 'WS Owned - ' + city, AccountId = office.get(city),
        StageName = 'Closed Won', CloseDate = Date.today(), Pricebook2Id = stdPb));
}
insert opps;
Map<String, Id> oppByCity = new Map<String, Id>();
for (Opportunity o : opps) oppByCity.put(o.Name.substringAfter('- '), o.Id);

List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
for (String city : owned.keySet()) {
    for (String spec : owned.get(city)) {
        olis.add(new OpportunityLineItem(
            OpportunityId = oppByCity.get(city), PricebookEntryId = pbeByName.get(spec.substringBefore(':')),
            Quantity = 1, UnitPrice = Decimal.valueOf(spec.substringAfter(':'))));
    }
}
insert olis;
System.debug('Seeded ' + opps.size() + ' won opps + ' + olis.size() + ' line items on Globex offices.');

// 5) Revert bypass for this user
delete bp;
