/*
 * REV-68 Step 5 — prove the conversion-orphaning baseline + validation rules.
 * Runs in a savepoint and ROLLS BACK at the end, leaving the sandbox clean.
 */
List<String> log = new List<String>();
Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

Account off = new Account(Name='REV68 Proof Office', RecordTypeId=officeRt, BillingCountryCode='GB', BillingCity='London');
insert off;
Lead ld = new Lead(FirstName='Test', LastName='ProofLead', Company='REV68 Proof', CountryCode='GB', Email='rev68-proof@demo.com');
insert ld;

// Two interactions on the Lead (one with Interaction_Code__c).
LBR_Interactions__c a = new LBR_Interactions__c(Lead__c=ld.Id, Interaction_Type__c='Member', Interaction_Status__c='Active', Interaction_Date__c=Date.today(), Interaction_Code__c='PROOF-A');
LBR_Interactions__c b = new LBR_Interactions__c(Lead__c=ld.Id, Interaction_Type__c='Event Delegate', Interaction_Status__c='Active', Interaction_Date__c=Date.today());
insert new List<LBR_Interactions__c>{a, b};
log.add('SETUP: inserted 2 interactions on Lead ' + ld.Id);

// ---- Validation rule checks --------------------------------------------------
// (a) neither Contact nor Lead
try {
    insert new LBR_Interactions__c(Interaction_Type__c='Member', Interaction_Status__c='Active', Interaction_Date__c=Date.today());
    log.add('VR (a) neither: FAIL - insert was allowed');
} catch (DmlException e) {
    log.add('VR (a) neither: BLOCKED -> ' + e.getDmlMessage(0));
}
// (b) both Contact and Lead
Contact someContact = new Contact(LastName='Both', AccountId=off.Id);
insert someContact;
try {
    insert new LBR_Interactions__c(Lead__c=ld.Id, Contact__c=someContact.Id, Interaction_Type__c='Member', Interaction_Status__c='Active', Interaction_Date__c=Date.today());
    log.add('VR (b) both: FAIL - insert was allowed');
} catch (DmlException e) {
    log.add('VR (b) both: BLOCKED -> ' + e.getDmlMessage(0));
}
// (c) a converted-lead Id
Lead convLead = new Lead(FirstName='Test', LastName='AlreadyConverted', Company='REV68 Proof', CountryCode='GB', Email='rev68-converted@demo.com');
insert convLead;
String convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted=true ORDER BY SortOrder NULLS LAST LIMIT 1].MasterLabel;
Database.LeadConvert lcC = new Database.LeadConvert();
lcC.setLeadId(convLead.Id); lcC.setConvertedStatus(convertedStatus); lcC.setAccountId(off.Id); lcC.setDoNotCreateOpportunity(true);
Database.LeadConvertResult lcrC = Database.convertLead(lcC, false);
if (lcrC.isSuccess()) {
    try {
        insert new LBR_Interactions__c(Lead__c=convLead.Id, Interaction_Type__c='Member', Interaction_Status__c='Active', Interaction_Date__c=Date.today());
        log.add('VR (c) converted-lead: FAIL - insert was allowed');
    } catch (DmlException e) {
        log.add('VR (c) converted-lead: BLOCKED -> ' + e.getDmlMessage(0));
    }
} else {
    log.add('VR (c) converted-lead: SKIPPED - could not convert helper lead (' + lcrC.getErrors()[0].getMessage() + ')');
}

// ---- Baseline: standard convert with NO reparent automation ------------------
Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId(ld.Id); lc.setConvertedStatus(convertedStatus); lc.setAccountId(off.Id); lc.setDoNotCreateOpportunity(false);
Database.LeadConvertResult lcr = Database.convertLead(lc, false);
if (!lcr.isSuccess()) {
    log.add('BASELINE: convert BLOCKED -> ' + lcr.getErrors()[0].getMessage());
} else {
    List<LBR_Interactions__c> afterConvert = [SELECT Id, Lead__c, Contact__c FROM LBR_Interactions__c WHERE Id IN (:a.Id, :b.Id)];
    Integer orphaned = 0;
    for (LBR_Interactions__c i : afterConvert) if (i.Lead__c != null && i.Contact__c == null) orphaned++;
    log.add('BASELINE: after standard convert, ' + orphaned + '/2 interactions still orphaned on the Lead (Contact null). Defect reproduced.');

    // ---- Post-fix: run the reparent service --------------------------------
    LBRInteractionReparentService.reparent(new List<LBRInteractionReparentService.ConvertedLead>{
        new LBRInteractionReparentService.ConvertedLead(ld.Id, lcr.getContactId(), lcr.getAccountId(), lcr.getOpportunityId())
    });
    List<LBR_Interactions__c> afterFix = [SELECT Id, Lead__c, Contact__c, Account__c, Ultimate_Account__c FROM LBR_Interactions__c WHERE Id IN (:a.Id, :b.Id)];
    Integer fixed = 0;
    for (LBR_Interactions__c i : afterFix) if (i.Lead__c == null && i.Contact__c == lcr.getContactId()) fixed++;
    log.add('POST-FIX: ' + fixed + '/2 interactions re-parented onto Contact ' + lcr.getContactId() + ' (Lead cleared).');
    Integer c2i = [SELECT COUNT() FROM Contact2Interaction__c WHERE LBR_Interactions__c IN (:a.Id, :b.Id)];
    log.add('POST-FIX: Contact2Interaction__c rows created (Opp present? ' + (lcr.getOpportunityId()!=null) + '): ' + c2i);
}

// Surface the summary via an unhandled assertion (also auto-rolls back all DML above).
System.assert(false, 'REV-68 PROOF :: ' + String.join(log, ' :: '));
