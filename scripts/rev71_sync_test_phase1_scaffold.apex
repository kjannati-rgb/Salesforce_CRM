// REV-71 — Step 2 sync verification, PHASE 1: scaffold quote stack (KJDEV only)
// Creates: 1 Account, 1 Opportunity (USD), 1 PRIMARY CPQ quote, 2 quote lines
// (LAWM net 5000, LNVM net 1000). CPQ's quote->opportunity sync should then
// create matching OpportunityLineItems. No code stamping in this phase.
// Pricebook: "ALM - Information Services" 01sTm000001U0TRIA0 (USD PBEs verified 12 Jun).

Id pbId = '01sTm000001U0TRIA0';
Id pbeLawm = '01uTm000003pfh1IAA'; // LAWM USD
Id pbeLnvm = '01uTm000003tH05IAE'; // LNVM USD

Account acc = new Account(Name = 'ZZ REV71 Sync Test Account');
insert acc;

Opportunity opp = new Opportunity(
    Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test',
    AccountId = acc.Id,
    StageName = 'Qualify',
    CloseDate = Date.today().addDays(30),
    CurrencyIsoCode = 'USD',
    Pricebook2Id = pbId
);
insert opp;

SBQQ__Quote__c q = new SBQQ__Quote__c(
    SBQQ__Account__c = acc.Id,
    SBQQ__Opportunity2__c = opp.Id,
    SBQQ__Primary__c = true,
    SBQQ__PriceBook__c = pbId,
    SBQQ__PricebookId__c = pbId,
    CurrencyIsoCode = 'USD',
    SBQQ__StartDate__c = Date.today(),
    SBQQ__SubscriptionTerm__c = 12
);
insert q;

Product2 lawm = [SELECT Id FROM Product2 WHERE ProductCode = 'LAWM' LIMIT 1];
Product2 lnvm = [SELECT Id FROM Product2 WHERE ProductCode = 'LNVM' LIMIT 1];

List<SBQQ__QuoteLine__c> qls = new List<SBQQ__QuoteLine__c>{
    new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = q.Id, SBQQ__Product__c = lawm.Id,
        SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = pbeLawm,
        SBQQ__ListPrice__c = 5000, SBQQ__CustomerPrice__c = 5000, SBQQ__NetPrice__c = 5000,
        SBQQ__Number__c = 1
    ),
    new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = q.Id, SBQQ__Product__c = lnvm.Id,
        SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = pbeLnvm,
        SBQQ__ListPrice__c = 1000, SBQQ__CustomerPrice__c = 1000, SBQQ__NetPrice__c = 1000,
        SBQQ__Number__c = 2
    )
};
insert qls;

System.debug('REV71_SCAFFOLD account=' + acc.Id + ' opp=' + opp.Id + ' quote=' + q.Id
    + ' ql1=' + qls[0].Id + ' ql2=' + qls[1].Id);
