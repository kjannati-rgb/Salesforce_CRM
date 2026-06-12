// REV-71 sync test 1d: drive CPQ's own Quote API (reader -> calculator -> saver)
// against the ZZ REV71-SYNC-01 test quote — the same path the QLE uses. The saver
// should clear SBQQ__Uncalculated__c and run primary-quote sync, creating OLIs.
Id quoteId = [
    SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
    LIMIT 1
].Id;

String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
System.debug('REV71_QAPI read ok, model length=' + quoteJson.length());

String calced;
try {
    calced = SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, '{"context":' + quoteJson + '}');
    System.debug('REV71_QAPI calculate ok, length=' + calced.length());
} catch (Exception e) {
    System.debug('REV71_QAPI calculate FAILED: ' + e.getMessage() + ' — falling back to saving the read model');
    calced = quoteJson;
}

String saved = SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', calced);
System.debug('REV71_QAPI save ok, length=' + saved.length());
