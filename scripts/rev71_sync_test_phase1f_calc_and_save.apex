// REV-71 sync test 1f: full headless QLE-equivalent — read, calculate, save the
// CALCULATED model. Save should clear SBQQ__Uncalculated__c and run primary-quote
// sync, creating OLIs for both lines.
Id quoteId = [
    SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
    LIMIT 1
].Id;

String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
System.debug('REV71_FULL read ok len=' + quoteJson.length());

String calced = SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, '{"quote":' + quoteJson + '}');
System.debug('REV71_FULL calculate ok len=' + calced.length());

String saved = SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', calced);
System.debug('REV71_FULL save ok len=' + saved.length());
