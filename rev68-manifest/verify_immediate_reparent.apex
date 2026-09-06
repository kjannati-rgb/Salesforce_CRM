// Verify the LeadConvertReparent trigger re-parents DURING a standard convert (no sweeper/invocable).
List<String> log = new List<String>();
Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
Account off = new Account(Name='LCR Verify Office', RecordTypeId=officeRt, BillingCountryCode='GB', BillingCity='London');
insert off;
Lead ld = new Lead(FirstName='Test', LastName='LCRVerify', Company='LCR Verify', CountryCode='GB', Email='lcr-verify@demo.com');
insert ld;
LBR_Interactions__c i1 = new LBR_Interactions__c(Lead__c=ld.Id, Interaction_Type__c='Member',
    Interaction_Status__c='Active', Interaction_Date__c=Date.today(), Interaction_Code__c='LCRV-1');
insert i1;
String cs = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted=true ORDER BY SortOrder NULLS LAST LIMIT 1].MasterLabel;
Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId(ld.Id); lc.setConvertedStatus(cs); lc.setAccountId(off.Id); lc.setDoNotCreateOpportunity(true);
Database.LeadConvertResult lcr = Database.convertLead(lc, false);
if (!lcr.isSuccess()) {
    log.add('CONVERT BLOCKED: ' + lcr.getErrors()[0].getMessage());
} else {
    LBR_Interactions__c a = [SELECT Contact__c, Lead__c FROM LBR_Interactions__c WHERE Id=:i1.Id];
    Boolean ok = (a.Contact__c == lcr.getContactId() && a.Lead__c == null);
    log.add((ok ? 'PASS' : 'FAIL') + ': after standard convert, Contact__c=' + a.Contact__c + ' Lead__c=' + a.Lead__c + ' (expected contact ' + lcr.getContactId() + ', lead null)');
}
System.assert(false, 'LCR_VERIFY :: ' + String.join(log, ' :: '));
