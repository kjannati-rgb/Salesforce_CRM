// REV-71 — READ-ONLY scan: in-flight (open/pending) ALM opps the engine WOULD code
// but that currently have a BLANK ALM Total Contract Value on standalone lines —
// i.e. deals whose product lines pre-date go-live and were never re-saved. No DML.
Set<String> gll = new Set<String>{'GLBM','GLBM - Team Membership','GLBM - Individual Membership'};

Set<Id> cand = new Set<Id>();
for (AggregateResult ar : [SELECT OpportunityId oid FROM OpportunityLineItem
        WHERE Opportunity.IsClosed = false AND Product2.Division__c = 'ALM'
          AND Full_Contract_Value__c = null AND SBQQ__ParentID__c = null
          AND Opportunity.StageName LIKE '%Approval%'
        GROUP BY OpportunityId LIMIT 2000]) {
    cand.add((Id) ar.get('oid'));
}

Map<Id, List<OpportunityLineItem>> byOpp = new Map<Id, List<OpportunityLineItem>>();
for (OpportunityLineItem o : [SELECT Id, OpportunityId, Opportunity.Name, Opportunity.StageName,
        Product2Id, ProductCode, TotalPrice, Full_Contract_Value__c, SBQQ__ParentID__c
        FROM OpportunityLineItem WHERE OpportunityId IN :cand]) {
    if (!byOpp.containsKey(o.OpportunityId)) byOpp.put(o.OpportunityId, new List<OpportunityLineItem>());
    byOpp.get(o.OpportunityId).add(o);
}

Integer gaps = 0; List<String> rows = new List<String>();
Map<Decimal,Integer> byCode = new Map<Decimal,Integer>{1=>0,2=>0,3=>0};
for (Id oid : byOpp.keySet()) {
    Set<Id> dp = new Set<Id>(); Boolean g=false, la=false, lw=false, blank=false;
    Map<String,Decimal> ft = new Map<String,Decimal>{'LAWM'=>0,'LWKM'=>0};
    String nm='', st='';
    for (OpportunityLineItem l : byOpp.get(oid)) {
        if (l.SBQQ__ParentID__c != null) continue;
        nm = l.Opportunity.Name; st = l.Opportunity.StageName;
        dp.add(l.Product2Id);
        String pc = l.ProductCode;
        if (gll.contains(pc)) g = true;
        if (pc == 'LAWM') { la = true; ft.put('LAWM', ft.get('LAWM') + (l.TotalPrice==null?0:l.TotalPrice)); }
        if (pc == 'LWKM') { lw = true; ft.put('LWKM', ft.get('LWKM') + (l.TotalPrice==null?0:l.TotalPrice)); }
        if (l.Full_Contract_Value__c == null) blank = true;
    }
    Decimal derived = null;
    if (dp.size() <= 1) derived = null;
    else if (g) derived = 2;
    else if (la && lw) derived = (ft.get('LAWM') >= ft.get('LWKM')) ? 1 : 3;
    else if (la) derived = 1;
    else if (lw) derived = 3;
    if (derived != null && blank) {
        gaps++; byCode.put(derived, byCode.get(derived) + 1);
        if (rows.size() < 200) rows.add(oid + ' | ' + nm + ' | ' + st + ' | would-be code ' + derived);
    }
}
System.debug('REV71_GAP ==== ' + gaps + ' in-flight ALM opps would be coded but have blank lines ====');
System.debug('REV71_GAP by code: 1=' + byCode.get(1) + ' 2=' + byCode.get(2) + ' 3=' + byCode.get(3));
for (String r : rows) System.debug('REV71_GAP ' + r);
