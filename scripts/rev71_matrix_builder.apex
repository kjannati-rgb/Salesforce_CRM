// REV-71 §6 matrix — SCENARIO BUILDER. Driver substitutes __N__ before each run.
// Creates the data for one scenario in one transaction (no callouts here; the
// calc/save step runs separately because CPQ's calculator does an HTTP callout,
// which Salesforce forbids after DML in the same transaction).
// Naming: every record is prefixed 'ZZ REV71-M<NN>' for clean teardown.

class Fx {
    Map<String, Product2> prods = new Map<String, Product2>();
    Map<String, Id> pbes = new Map<String, Id>();
    Id pbId;
    Fx() {
        pbId = [SELECT Id FROM Pricebook2 WHERE Name = 'ALM - Information Services' LIMIT 1].Id;
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN
                ('LAWM','LNVM','LWKM','TALM','GLBM','NYLM','Law.com Pro','Law.com Premium Bundle')]) {
            prods.put(p.ProductCode, p);
        }
        for (PricebookEntry e : [SELECT Id, Product2.ProductCode FROM PricebookEntry
                WHERE Pricebook2Id = :pbId AND CurrencyIsoCode = 'USD' AND IsActive = true
                AND Product2.ProductCode IN :prods.keySet()]) {
            pbes.put(e.Product2.ProductCode, e.Id);
        }
    }
    SBQQ__QuoteLine__c ql(Id qId, String code, Decimal price, Integer num) {
        return new SBQQ__QuoteLine__c(SBQQ__Quote__c = qId, SBQQ__Product__c = prods.get(code).Id,
            SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = pbes.get(code),
            SBQQ__ListPrice__c = price, SBQQ__CustomerPrice__c = price, SBQQ__NetPrice__c = price,
            SBQQ__Number__c = num);
    }
    OpportunityLineItem oli(Id oppId, String code, Decimal price, String parentId) {
        return new OpportunityLineItem(OpportunityId = oppId, PricebookEntryId = pbes.get(code),
            Quantity = 1, UnitPrice = price, SBQQ__ParentID__c = parentId);
    }
    SBQQ__Quote__c quote(Id accId, Id oppId, Boolean primary) {
        return new SBQQ__Quote__c(SBQQ__Account__c = accId, SBQQ__Opportunity2__c = oppId,
            SBQQ__Primary__c = primary, SBQQ__PriceBook__c = pbId, SBQQ__PricebookId__c = pbId,
            CurrencyIsoCode = 'USD', SBQQ__StartDate__c = Date.today(), SBQQ__SubscriptionTerm__c = 12);
    }
}

Integer N = __N__;
String tag = 'ZZ REV71-M' + String.valueOf(N).leftPad(2, '0');
Fx fx = new Fx();

Account acc = new Account(Name = tag + ' Account');
insert acc;
Opportunity opp = new Opportunity(Name = tag, AccountId = acc.Id, StageName = 'Qualify',
    CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'USD', Pricebook2Id = fx.pbId);
insert opp;

Boolean needsQuote = !(N == 16 || N == 21 || N == 22);
SBQQ__Quote__c q;
if (needsQuote) {
    q = fx.quote(acc.Id, opp.Id, N != 18); // scenario 18: primary AFTER stamping (creation-sync test)
    insert q;
}

List<SBQQ__QuoteLine__c> qls = new List<SBQQ__QuoteLine__c>();
if (N == 1) {                                    // 1 product, 1 year -> no code
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1));
} else if (N == 2 || N == 14) {                  // Law.com Pro bundle (+LNVM standalone for 14)
    SBQQ__QuoteLine__c parent = fx.ql(q.Id, 'Law.com Pro', 9000, 1);
    insert parent;
    List<SBQQ__ProductOption__c> opts = [SELECT Id, SBQQ__OptionalSKU__c
        FROM SBQQ__ProductOption__c
        WHERE SBQQ__ConfiguredSKU__c = :fx.prods.get('Law.com Pro').Id LIMIT 2];
    for (Integer i = 0; i < opts.size(); i++) {
        qls.add(new SBQQ__QuoteLine__c(SBQQ__Quote__c = q.Id,
            SBQQ__Product__c = opts[i].SBQQ__OptionalSKU__c, SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = 0, SBQQ__CustomerPrice__c = 0, SBQQ__NetPrice__c = 0,
            SBQQ__Number__c = 2 + i, SBQQ__RequiredBy__c = parent.Id,
            SBQQ__ProductOption__c = opts[i].Id));
    }
    if (N == 14) qls.add(fx.ql(q.Id, 'LNVM', 1000, 9));
} else if (N == 3) {
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LNVM', 1000, 2));
} else if (N == 4) {                             // 2 years = 2 lines per product
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LAWM', 5200, 2));
    qls.add(fx.ql(q.Id, 'LNVM', 1000, 3)); qls.add(fx.ql(q.Id, 'LNVM', 1050, 4));
} else if (N == 5) {
    qls.add(fx.ql(q.Id, 'GLBM', 10000, 1)); qls.add(fx.ql(q.Id, 'LAWM', 5000, 2));
} else if (N == 6) {
    qls.add(fx.ql(q.Id, 'GLBM', 10000, 1)); qls.add(fx.ql(q.Id, 'LWKM', 4000, 2));
} else if (N == 7 || N == 12) {                  // LAWM pricier -> 1 (12 repriced later)
    qls.add(fx.ql(q.Id, 'LAWM', 8000, 1)); qls.add(fx.ql(q.Id, 'LWKM', 4000, 2));
} else if (N == 8) {                             // LWKM pricier -> 3
    qls.add(fx.ql(q.Id, 'LAWM', 4000, 1)); qls.add(fx.ql(q.Id, 'LWKM', 8000, 2));
} else if (N == 9) {
    qls.add(fx.ql(q.Id, 'LWKM', 5000, 1)); qls.add(fx.ql(q.Id, 'TALM', 2000, 2));
} else if (N == 10 || N == 11) {                 // base deal; 10 adds a line later, 11 deletes one
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LNVM', 1000, 2));
} else if (N == 13) {                            // no anchor -> no code + visibility log
    qls.add(fx.ql(q.Id, 'LNVM', 1000, 1)); qls.add(fx.ql(q.Id, 'NYLM', 1200, 2));
} else if (N == 15) {                            // bulk: 10 quotes x 20 lines = 200
    List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
    for (Integer i = 0; i < 10; i++) quotes.add(fx.quote(acc.Id, opp.Id, false));
    insert quotes;
    List<String> mix = new List<String>{'LAWM','LNVM','TALM','NYLM'};
    for (SBQQ__Quote__c bq : quotes) {
        for (Integer i = 0; i < 20; i++) {
            qls.add(fx.ql(bq.Id, mix[Math.mod(i, 4)], 100 * (i + 1), i + 1));
        }
    }
} else if (N == 17 || N == 18) {
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LNVM', 1000, 2));
} else if (N == 19) {                            // renewal-type quote (approximation; see runbook note)
    q.SBQQ__Type__c = 'Renewal'; update q;
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LNVM', 1000, 2));
} else if (N == 20) {                            // amendment-type quote (approximation)
    q.SBQQ__Type__c = 'Amendment'; update q;
    qls.add(fx.ql(q.Id, 'LAWM', 5000, 1)); qls.add(fx.ql(q.Id, 'LWKM', 8000, 2));
} else if (N == 16) {                            // legacy inactive bundle, OLI-only historical opp
    insert new List<OpportunityLineItem>{
        fx.oli(opp.Id, 'Law.com Premium Bundle', 9000, null),
        fx.oli(opp.Id, 'LNVM', 0, 'a1ELEGACYCHILD0001'),
        fx.oli(opp.Id, 'NYLM', 0, 'a1ELEGACYCHILD0002'),
        fx.oli(opp.Id, 'LAWM', 5000, null),
        fx.oli(opp.Id, 'TALM', 2000, null)
    };
} else if (N == 21 || N == 22) {                 // manual OLIs, no quote -> Layer 2 path
    insert new List<OpportunityLineItem>{
        fx.oli(opp.Id, 'LAWM', 5000, null),
        fx.oli(opp.Id, 'LNVM', 1000, null)
    };
}
if (!qls.isEmpty()) insert qls;

System.debug('REV71_MX_BUILD N=' + N + ' tag=' + tag + ' opp=' + opp.Id
    + ' quote=' + (q == null ? 'none' : String.valueOf(q.Id)) + ' qls=' + qls.size());
