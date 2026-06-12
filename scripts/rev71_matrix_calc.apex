// REV-71 §6 matrix — CALCULATE+SAVE step for scenario __N__, quote index __QIDX__.
// Strictly ONE quote per transaction: the CPQ calculator is an HTTP callout and
// callouts are forbidden after DML (the saver) in the same transaction, so the
// driver loops this script per quote (scenario 15 has ten).
Integer N = __N__;
Integer qIdx = __QIDX__;
String tag = 'ZZ REV71-M' + String.valueOf(N).leftPad(2, '0');
List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Opportunity2__r.Name = :tag ORDER BY Id];
if (qIdx >= quotes.size()) {
    System.debug('REV71_MX_CALC N=' + N + ' qIdx=' + qIdx + ' SKIP (only ' + quotes.size() + ' quotes)');
} else {
    Id qId = quotes[qIdx].Id;
    String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', qId);
    String calced = SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, '{"quote":' + quoteJson + '}');
    SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', calced);
    System.debug('REV71_MX_CALC N=' + N + ' qIdx=' + qIdx + ' quote=' + qId + ' ok');
}
