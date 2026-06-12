// REV-71 smoke test prep: remove the phase-2 MANUAL stamps from the ZZ scaffold
// (quote lines + OLIs to null) so the deployed engine can be observed stamping
// codes itself on the next calculate/save.
List<SBQQ__QuoteLine__c> qls = [
    SELECT Id FROM SBQQ__QuoteLine__c
    WHERE SBQQ__Quote__r.SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
];
for (SBQQ__QuoteLine__c ql : qls) ql.Full_Contract_Value__c = null;
update qls;
List<OpportunityLineItem> olis = [
    SELECT Id FROM OpportunityLineItem
    WHERE Opportunity.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
];
for (OpportunityLineItem oli : olis) oli.Full_Contract_Value__c = null;
update olis;
System.debug('REV71_SMOKE_CLEAR qls=' + qls.size() + ' olis=' + olis.size());
