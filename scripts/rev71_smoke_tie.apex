// REV-71 LIVE SMOKE TEST — tie-break (exact-equal LAWM vs LWKM revenue -> code 1).
// KJDEV only. Creates ONE clearly-named deal 'ZZ REV71-SMOKE-TIE 15Jun' by cloning the
// existing ZZ REV71-M08 opp (so it inherits a valid record type / required fields and
// passes VRs), then inserts two MANUAL OpportunityLineItems with identical TotalPrice.
// Inserting the lines flips Opp.HasOpportunityLineItem/Amount -> fires Layer 2
// (Opp_ALM_Code_AfterSave), which derives + stamps Full_Contract_Value__c.
// Brady (15 Jun 2026): an exact revenue tie resolves to code 1. We assert code == 1.
// Idempotent: deletes any prior SMOKE-TIE deal first. Restores user bypass at the end.

final Id LAWM_PBE = '01uTm000003pfh1IAA';
final Id LWKM_PBE = '01uTm000003tGqPIAU';
final String SMOKE_NAME = 'ZZ REV71-SMOKE-TIE 15Jun';

// --- 1. user-level bypass: VRs off, automation ON (so Layer 2 still fires) ---
Id me = UserInfo.getUserId();
List<Application_Settings__c> mine = [SELECT Id, Disable_Validation_Rules__c,
    Disable_Autolaunch_Lightning_Flow__c FROM Application_Settings__c WHERE SetupOwnerId = :me LIMIT 1];
Boolean hadRow = !mine.isEmpty();
Application_Settings__c row = hadRow ? mine[0]
    : new Application_Settings__c(SetupOwnerId = me);
Boolean prevVR = hadRow ? row.Disable_Validation_Rules__c : null;
Boolean prevFlow = hadRow ? row.Disable_Autolaunch_Lightning_Flow__c : null;
row.Disable_Validation_Rules__c = true;
row.Disable_Autolaunch_Lightning_Flow__c = false;
upsert row;

// --- 2. clean any prior smoke deal ---
delete [SELECT Id FROM Opportunity WHERE Name = :SMOKE_NAME];

// --- 3. clone M08 opp for a valid, VR-passing shell (no lines copied) ---
Opportunity src = [SELECT Id FROM Opportunity WHERE Name = 'ZZ REV71-M08' LIMIT 1];
Opportunity smoke = [SELECT Id, AccountId, Pricebook2Id, RecordTypeId, CurrencyIsoCode,
    StageName, CloseDate, Type, LeadSource FROM Opportunity WHERE Id = :src.Id].deepClone(false, false, false);
smoke.Name = SMOKE_NAME;
insert smoke;
System.debug('SMOKE >>> created Opp ' + smoke.Id + '  (PB ' + smoke.Pricebook2Id + ')');

// --- 4. two MANUAL lines, identical revenue (the tie) ---
Decimal tie = 5000;
insert new List<OpportunityLineItem>{
    new OpportunityLineItem(OpportunityId = smoke.Id, PricebookEntryId = LAWM_PBE, Quantity = 1, UnitPrice = tie),
    new OpportunityLineItem(OpportunityId = smoke.Id, PricebookEntryId = LWKM_PBE, Quantity = 1, UnitPrice = tie)
};

// --- 5. read back what Layer 2 stamped (same transaction) ---
System.debug('SMOKE >>> tie = LAWM ' + tie + '  vs  LWKM ' + tie);
Boolean pass = true;
for (OpportunityLineItem o : [SELECT PricebookEntry.Product2.ProductCode, TotalPrice,
        Full_Contract_Value__c FROM OpportunityLineItem WHERE OpportunityId = :smoke.Id
        ORDER BY PricebookEntry.Product2.ProductCode]) {
    System.debug('SMOKE >>>   ' + o.PricebookEntry.Product2.ProductCode
        + '  total=' + o.TotalPrice + '  code=' + o.Full_Contract_Value__c);
    if (o.Full_Contract_Value__c != 1) pass = false;
}
System.debug('SMOKE >>> RESULT: ' + (pass ? 'PASS — exact tie resolved to code 1 (Brady-confirmed)'
    : 'FAIL — expected code 1 on every line'));

// --- 6. restore user bypass to its prior state ---
if (hadRow) {
    row.Disable_Validation_Rules__c = prevVR;
    row.Disable_Autolaunch_Lightning_Flow__c = prevFlow;
    update row;
} else {
    delete row;
}
System.debug('SMOKE >>> bypass restored; deal left in place as ' + SMOKE_NAME);
