/**
 * FSS §8.2 — reconciliation: new USD rollups vs legacy Rollup Helper (rh2).
 * Run anonymous:  sf apex run --file scripts/firm-sales-summary/reconcile.apex --target-org KJDEV
 *
 * Asserts COUNT parity exactly against the rh2 opp set (both count Closed Won under the firm).
 * For VALUE, the new figure is expected to differ (new = USD + cancellation-netting + dated basis;
 * rh2 = legacy GBP/record-currency, Closed Won only) — the deltas are reported and explained, not
 * "fixed". Also checks Σ(group values) ≈ firm Net Won Value.
 *
 * NOTE: meaningful only where rh2 data exists (production). In an empty sandbox it reports 0 firms.
 */
Integer SAMPLE = 50;
List<Account> firms = [
    SELECT Id, Name,
           No_of_Won_Office_Opportunities__c, Val_of_Won_Office_Opportunities__c,
           Firm_Won_Count_AllTime__c, Firm_Won_Value_AllTime_USD__c,
           Firm_Cancellation_Value_AllTime_USD__c,
           (SELECT Won_Value_AllTime_USD__c FROM Firm_Product_Group_Rollups__r)
    FROM Account
    WHERE RecordType.DeveloperName = 'Firm'
      AND No_of_Won_Office_Opportunities__c != null
    ORDER BY No_of_Won_Office_Opportunities__c DESC NULLS LAST
    LIMIT :SAMPLE];

System.debug('=== FSS reconciliation: ' + firms.size() + ' sample firm(s) ===');
Integer countMatches = 0, countMismatches = 0;
for (Account a : firms) {
    Integer rh2Count = (a.No_of_Won_Office_Opportunities__c == null) ? 0 : a.No_of_Won_Office_Opportunities__c.intValue();
    Integer newCount = (a.Firm_Won_Count_AllTime__c == null) ? 0 : a.Firm_Won_Count_AllTime__c.intValue();
    Boolean countOk = (rh2Count == newCount);
    if (countOk) countMatches++; else countMismatches++;

    Decimal sumGroups = 0;
    for (Firm_Product_Group_Rollup_USD__c g : a.Firm_Product_Group_Rollups__r) {
        sumGroups += (g.Won_Value_AllTime_USD__c == null ? 0 : g.Won_Value_AllTime_USD__c);
    }
    Decimal net = (a.Firm_Won_Value_AllTime_USD__c == null ? 0 : a.Firm_Won_Value_AllTime_USD__c);
    Decimal groupDeltaPct = (net == 0) ? 0 : ((sumGroups - net) / net * 100).setScale(2);

    System.debug(
        a.Name +
        ' | COUNT rh2=' + rh2Count + ' new=' + newCount + (countOk ? ' OK' : ' MISMATCH') +
        ' | VALUE rh2(legacy GBP, CW-only)=' + a.Val_of_Won_Office_Opportunities__c +
        ' new(USD net)=' + net + ' cancUSD=' + a.Firm_Cancellation_Value_AllTime_USD__c +
        ' | ΣgroupsUSD=' + sumGroups + ' (Δ ' + groupDeltaPct + '% vs net)');
}
System.debug('=== COUNT parity: ' + countMatches + ' match / ' + countMismatches + ' mismatch ===');
System.debug('Value differences are expected and structural: new = USD (dated FX) + cancellation-netting;');
System.debug('rh2 = record-currency/legacy GBP, Closed Won only. Σgroups should track firm net within FX grain.');
