// REV-71 READ-ONLY — test the VAR-rule hypothesis against production.
// Among coded deals that contain BOTH LAWM and LWKM standalone lines (no GLL),
// how often is the deal coded 3 (International) vs 1 (Law.com), and within each,
// which anchor was actually pricier? If "coded 3" dominates even when LAWM is
// pricier, the spec's highest-price rule is wrong and International is decisive.
Map<Id, Decimal> lawmTot = new Map<Id, Decimal>();
Map<Id, Decimal> lwkmTot = new Map<Id, Decimal>();
Map<Id, Boolean> hasGLL = new Map<Id, Boolean>();
Map<Id, Decimal> code = new Map<Id, Decimal>();

Set<Id> codedOpps = new Set<Id>();
for (AggregateResult ar : [SELECT OpportunityId oid FROM OpportunityLineItem
        WHERE Full_Contract_Value__c IN (1,2,3) GROUP BY OpportunityId]) {
    codedOpps.add((Id) ar.get('oid'));
}
for (OpportunityLineItem o : [
        SELECT OpportunityId, ProductCode, TotalPrice, Full_Contract_Value__c, SBQQ__ParentID__c
        FROM OpportunityLineItem
        WHERE OpportunityId IN :codedOpps
          AND SBQQ__ParentID__c = null]) {
    Id k = o.OpportunityId;
    if (o.ProductCode == 'LAWM') lawmTot.put(k, (lawmTot.containsKey(k)?lawmTot.get(k):0) + (o.TotalPrice==null?0:o.TotalPrice));
    if (o.ProductCode == 'LWKM') lwkmTot.put(k, (lwkmTot.containsKey(k)?lwkmTot.get(k):0) + (o.TotalPrice==null?0:o.TotalPrice));
    if (o.ProductCode != null && o.ProductCode.startsWith('GLBM')) hasGLL.put(k, true);
    if (o.Full_Contract_Value__c != null && !code.containsKey(k)) code.put(k, o.Full_Contract_Value__c);
}

Integer both=0, coded3=0, coded1=0, codedOther=0;
Integer lawmPricier_coded3=0, lawmPricier_coded1=0, lwkmPricier_coded3=0, lwkmPricier_coded1=0;
for (Id k : lawmTot.keySet()) {
    if (!lwkmTot.containsKey(k)) continue;        // need BOTH
    if (hasGLL.get(k) == true) continue;          // exclude GLL (decisive -> 2)
    both++;
    Decimal c = code.get(k);
    Boolean lawmPricier = lawmTot.get(k) >= lwkmTot.get(k);
    if (c == 3) { coded3++; if (lawmPricier) lawmPricier_coded3++; else lwkmPricier_coded3++; }
    else if (c == 1) { coded1++; if (lawmPricier) lawmPricier_coded1++; else lwkmPricier_coded1++; }
    else codedOther++;
}
System.debug('REV71_VAR deals with BOTH LAWM+LWKM (no GLL): ' + both);
System.debug('REV71_VAR  coded 3 (International): ' + coded3);
System.debug('REV71_VAR  coded 1 (Law.com): ' + coded1);
System.debug('REV71_VAR  coded other: ' + codedOther);
System.debug('REV71_VAR  --- price vs code cross-tab ---');
System.debug('REV71_VAR  LAWM pricier & coded 3 (price rule WRONG): ' + lawmPricier_coded3);
System.debug('REV71_VAR  LAWM pricier & coded 1 (price rule right): ' + lawmPricier_coded1);
System.debug('REV71_VAR  LWKM pricier & coded 3 (price rule right): ' + lwkmPricier_coded3);
System.debug('REV71_VAR  LWKM pricier & coded 1 (price rule WRONG): ' + lwkmPricier_coded1);
