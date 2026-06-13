// REV-71 §7 — BACKFILL CONSISTENCY AUDIT (READ-ONLY; NO DML).
// For every opportunity that currently carries an ALM code, re-derive the code the
// REV-71 engine WOULD assign (spec §4 logic, mirrored here) and compare to what's
// stored. Emits a categorised mismatch summary so finance/Cayla can size the
// correction backlog before any remediation. Safe to run in PRODUCTION — it only
// queries and System.debugs; it writes nothing.
//
// IMPORTANT: this re-derivation uses the CURRENT engine rules. If Cayla revises the
// edge-case rules (bundle children, lone bundles, cross-family absorption), update
// the deriveCode() logic to match before treating mismatches as actionable.
//
// Run:  sf apex run -f scripts/rev71_backfill_audit.apex -o LBR_PROD   (read-only)

// ---- Config mirror (would be read from ALM_Code_Setting__mdt in the flow) ----
Map<String, Decimal> anchorToCode = new Map<String, Decimal>{
    'LAWM' => 1, 'LWKM' => 3,
    'GLBM' => 2, 'GLBM - Team Membership' => 2, 'GLBM - Individual Membership' => 2
};
Set<String> gllAnchors = new Set<String>{'GLBM','GLBM - Team Membership','GLBM - Individual Membership'};

// ---- Pull all coded deals' lines (Full_Contract_Value__c IN (1,2,3)) ----
Set<Id> codedOppIds = new Set<Id>();
for (AggregateResult ar : [
        SELECT OpportunityId oid FROM OpportunityLineItem
        WHERE Full_Contract_Value__c IN (1,2,3) GROUP BY OpportunityId]) {
    codedOppIds.add((Id) ar.get('oid'));
}

Map<Id, List<OpportunityLineItem>> byOpp = new Map<Id, List<OpportunityLineItem>>();
for (OpportunityLineItem oli : [
        SELECT Id, OpportunityId, Product2Id, Product2.ProductCode, ProductCode,
               TotalPrice, Full_Contract_Value__c, SBQQ__ParentID__c
        FROM OpportunityLineItem
        WHERE OpportunityId IN :codedOppIds]) {
    if (!byOpp.containsKey(oli.OpportunityId)) byOpp.put(oli.OpportunityId, new List<OpportunityLineItem>());
    byOpp.get(oli.OpportunityId).add(oli);
}

// ---- Counters ----
Integer oppsAudited = 0, oppsMatch = 0, oppsCodeMismatch = 0, oppsPartial = 0,
        oppsNoAnchor = 0, oppsChildCoded = 0;
List<String> samples = new List<String>();

for (Id oppId : byOpp.keySet()) {
    oppsAudited++;
    List<OpportunityLineItem> lines = byOpp.get(oppId);

    // standalone = not a CPQ child (ParentID null). distinct products + family signals.
    Set<Id> distinctProducts = new Set<Id>();
    Boolean hasGLL = false, hasLAWM = false, hasLWKM = false;
    Map<String, Decimal> familyTotals = new Map<String, Decimal>{'LAWM'=>0,'LWKM'=>0};
    Decimal storedCode = null;
    Boolean anyChildCoded = false, anyStandaloneBlank = false;

    for (OpportunityLineItem l : lines) {
        Boolean isChild = l.SBQQ__ParentID__c != null;
        if (l.Full_Contract_Value__c != null && isChild) anyChildCoded = true;
        if (isChild) continue;
        distinctProducts.add(l.Product2Id);
        String pc = l.ProductCode;
        if (gllAnchors.contains(pc)) hasGLL = true;
        if (pc == 'LAWM') { hasLAWM = true; familyTotals.put('LAWM', familyTotals.get('LAWM') + (l.TotalPrice==null?0:l.TotalPrice)); }
        if (pc == 'LWKM') { hasLWKM = true; familyTotals.put('LWKM', familyTotals.get('LWKM') + (l.TotalPrice==null?0:l.TotalPrice)); }
        if (l.Full_Contract_Value__c != null && storedCode == null) storedCode = l.Full_Contract_Value__c;
        if (l.Full_Contract_Value__c == null) anyStandaloneBlank = true;
    }

    // derive per spec §4
    Decimal derived = null;
    if (distinctProducts.size() <= 1) {
        derived = null;                       // single product / lone bundle -> no code
    } else if (hasGLL) {
        derived = 2;
    } else if (hasLAWM && hasLWKM) {
        derived = (familyTotals.get('LAWM') >= familyTotals.get('LWKM')) ? 1 : 3;
    } else if (hasLAWM) {
        derived = 1;
    } else if (hasLWKM) {
        derived = 3;
    } else {
        derived = null;                       // no anchor
    }

    if (anyChildCoded) oppsChildCoded++;
    if (anyStandaloneBlank) oppsPartial++;

    if (derived == null && storedCode != null) {
        oppsNoAnchor++;
        if (samples.size() < 25) samples.add(oppId + ' STORED=' + storedCode + ' DERIVED=none (no-anchor/single-product per current rules)');
    } else if (derived != null && storedCode != null && derived != storedCode) {
        oppsCodeMismatch++;
        if (samples.size() < 25) samples.add(oppId + ' STORED=' + storedCode + ' DERIVED=' + derived
            + ' GLL=' + hasGLL + ' LAWM=' + familyTotals.get('LAWM') + ' LWKM=' + familyTotals.get('LWKM'));
    } else {
        oppsMatch++;
    }
}

System.debug('REV71_AUDIT ==== SUMMARY ====');
System.debug('REV71_AUDIT opps audited           : ' + oppsAudited);
System.debug('REV71_AUDIT code MATCHES derived    : ' + oppsMatch);
System.debug('REV71_AUDIT code MISMATCH (wrong)   : ' + oppsCodeMismatch);
System.debug('REV71_AUDIT stored code but DERIVED none (no anchor / single product): ' + oppsNoAnchor);
System.debug('REV71_AUDIT deals with a BLANK standalone line (partial manual coding): ' + oppsPartial);
System.debug('REV71_AUDIT deals with a CODED bundle child (anomaly): ' + oppsChildCoded);
System.debug('REV71_AUDIT ---- sample mismatches (max 25) ----');
for (String s : samples) System.debug('REV71_AUDIT  ' + s);
