// Gate D seed: firm-level subscriptions for the Account Context card + a fit score for the gauge
List<Application_Settings__c> existing = [SELECT Id FROM Application_Settings__c WHERE SetupOwnerId = :UserInfo.getUserId()];
Application_Settings__c bypass = existing.isEmpty() ? new Application_Settings__c(SetupOwnerId = UserInfo.getUserId()) : existing[0];
bypass.Disable_Validation_Rules__c = true;
bypass.Disable_Autolaunch_Lightning_Flow__c = true;
bypass.Disable_Process_Builders__c = true;
upsert bypass;

Account firm = [SELECT Id, RecordTypeId FROM Account WHERE Name = 'Gate C Test Firm LLP' LIMIT 1];
Schema.RecordTypeInfo firmRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm');
if (firmRt != null && firm.RecordTypeId != firmRt.getRecordTypeId()) {
    firm.RecordTypeId = firmRt.getRecordTypeId();
    update firm;
}

List<Product2> prods = new List<Product2>();
Map<String, Integer> plan = new Map<String, Integer>{
    'Subs - Specialist Platforms' => 3,
    'Subs - Lexology Pro' => 2,
    'Performance Data - Lexology Index' => 1
};
// valid Division/Reporting_Stream pair (restricted dependent picklist)
List<Schema.PicklistEntry> divisions = Product2.Division__c.getDescribe().getPicklistValues();
String divVal; String streamVal;
for (Schema.PicklistEntry stream : Product2.Reporting_Stream__c.getDescribe().getPicklistValues()) {
    if (!stream.isActive()) continue;
    String validFor = (String) ((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(stream))).get('validFor');
    if (String.isBlank(validFor)) continue;
    String b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (Integer i = 0; i < divisions.size() && divVal == null; i++) {
        Integer charIdx = i / 6;
        if (charIdx >= validFor.length()) continue;
        Integer sextet = b64.indexOf(validFor.substring(charIdx, charIdx + 1));
        Integer bit = 5 - Math.mod(i, 6);
        if (divisions[i].isActive() && sextet >= 0 && (sextet & (1 << bit)) != 0) {
            divVal = divisions[i].getValue();
            streamVal = stream.getValue();
        }
    }
    if (divVal != null) break;
}
for (String fam : plan.keySet()) {
    prods.add(new Product2(Name = 'GATED ' + fam, Family = fam, Division__c = divVal,
        Reporting_Stream__c = streamVal, IsActive = true));
}
insert prods;

List<SBQQ__Subscription__c> subs = new List<SBQQ__Subscription__c>();
for (Product2 p : prods) {
    for (Integer i = 0; i < plan.get(p.Family); i++) {
        subs.add(new SBQQ__Subscription__c(
            Ultimate_Parent__c = firm.Id, SBQQ__Account__c = firm.Id, SBQQ__Product__c = p.Id,
            SBQQ__SubscriptionStartDate__c = Date.today().addDays(-60),
            SBQQ__SubscriptionEndDate__c = Date.today().addDays(305),
            SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 900, CurrencyIsoCode = 'GBP'));
    }
}
insert subs;
System.debug('GATED subs inserted: ' + subs.size());

// Simulated Clay score on the lead-linked Gate C record so the gauge renders
Pardot_Form_Completion__c pfc = [SELECT Id FROM Pardot_Form_Completion__c WHERE Id = 'a5EAe00000GHccMMAT'];
pfc.Fit_Score__c = 83;
pfc.Score_Reasoning__c = 'Senior in-house counsel at a high-growth technology company; EMEA employment remit matches Lexology PRO in-house ICP. (Simulated Clay output for Gate D walkthrough.)';
pfc.Clay_Routed__c = true;
update pfc;
System.debug('GATED score stamped');
