// REV-71 §6 matrix — MUTATION step for scenarios needing a second action.
// Driver substitutes __N__; runs AFTER the initial calc and BEFORE a re-calc.
Integer N = __N__;
String tag = 'ZZ REV71-M' + String.valueOf(N).leftPad(2, '0');

if (N == 10) {
    // Add a line to a coded deal -> expect all lines re-stamped on re-save
    SBQQ__Quote__c q = [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Opportunity2__r.Name = :tag LIMIT 1];
    Product2 talm = [SELECT Id FROM Product2 WHERE ProductCode = 'TALM' LIMIT 1];
    Id pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :talm.Id AND CurrencyIsoCode = 'USD'
              AND IsActive = true AND Pricebook2.Name = 'ALM - Information Services' LIMIT 1].Id;
    insert new SBQQ__QuoteLine__c(SBQQ__Quote__c = q.Id, SBQQ__Product__c = talm.Id,
        SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = pbe, SBQQ__ListPrice__c = 2000,
        SBQQ__CustomerPrice__c = 2000, SBQQ__NetPrice__c = 2000, SBQQ__Number__c = 3);
    System.debug('REV71_MX_MUT N=10 added TALM line');
} else if (N == 11) {
    // Delete a line so the deal drops to 1 product -> expect code cleared on re-save
    delete [SELECT Id FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__r.SBQQ__Opportunity2__r.Name = :tag
              AND SBQQ__Product__r.ProductCode = 'LNVM'];
    System.debug('REV71_MX_MUT N=11 deleted LNVM line');
} else if (N == 12) {
    // Reprice so LWKM overtakes LAWM -> expect code flips 1 -> 3 on re-save
    List<SBQQ__QuoteLine__c> qls = [SELECT Id, SBQQ__Product__r.ProductCode
        FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Opportunity2__r.Name = :tag];
    for (SBQQ__QuoteLine__c ql : qls) {
        Boolean isLawm = ql.SBQQ__Product__r.ProductCode == 'LAWM';
        ql.SBQQ__ListPrice__c = isLawm ? 3000 : 9000;
        ql.SBQQ__CustomerPrice__c = ql.SBQQ__ListPrice__c;
        ql.SBQQ__NetPrice__c = ql.SBQQ__ListPrice__c;
    }
    update qls;
    System.debug('REV71_MX_MUT N=12 repriced: LWKM now pricier');
} else if (N == 16) {
    // Edit the historical opp's OLIs (touch a price) -> Layer 2 re-evaluates
    OpportunityLineItem o = [SELECT Id, UnitPrice FROM OpportunityLineItem
        WHERE Opportunity.Name = :tag AND PricebookEntry.Product2.ProductCode = 'TALM' LIMIT 1];
    o.UnitPrice = o.UnitPrice + 1;
    update o;
    System.debug('REV71_MX_MUT N=16 touched legacy opp OLI');
} else if (N == 18) {
    // Make the (already stamped) quote primary -> CPQ creates OLIs; twin sync carries codes
    SBQQ__Quote__c q = [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Opportunity2__r.Name = :tag LIMIT 1];
    q.SBQQ__Primary__c = true;
    update q;
    System.debug('REV71_MX_MUT N=18 quote made primary');
} else if (N == 22) {
    // Simulate a sync-originated OLI write carrying the already-correct code ->
    // expect no recursion / values stable (Layer 2 must not even fire: Amount unchanged)
    List<OpportunityLineItem> olis = [SELECT Id, Full_Contract_Value__c
        FROM OpportunityLineItem WHERE Opportunity.Name = :tag];
    update olis; // no-op field-wise; proves a same-value touch causes no churn
    System.debug('REV71_MX_MUT N=22 re-saved OLIs unchanged');
}
