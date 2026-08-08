// REV-71 sync test 1e: retry CPQ Calculate API with documented payload shape
// {"quote": <QuoteModel>, "callbackClass": null} — calculator persists results
// and should clear SBQQ__Uncalculated__c, unblocking primary-quote sync.
Id quoteId = [
    SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = 'ZZ REV71-SYNC-01 Twin Field Sync Test'
    LIMIT 1
].Id;

String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
System.debug('REV71_CALC read ok len=' + quoteJson.length());
try {
    String payload = '{"quote":' + quoteJson + '}';
    String result = SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, payload);
    System.debug('REV71_CALC calculate ok len=' + (result == null ? -1 : result.length()));
} catch (Exception e) {
    System.debug('REV71_CALC calculate FAILED: ' + e.getTypeName() + ': ' + e.getMessage());
}
