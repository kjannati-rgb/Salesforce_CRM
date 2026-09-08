/**
 * Finance approver split - part 3 of 3: THE SWITCH (one transaction)
 * Run: sf apex run --file scripts/finance_split_3_activate.apex -o <org>
 *   - activates every "<legacy rule> - Amendments" clone
 *   - repoints the LBR originals (currently -> "Finance Approvers - Quote") to the core "Credit Control" approver
 * Rollback = deactivate the clones + repoint LBR originals back to "Finance Approvers - Quote".
 */
sbaa__Approver__c core = [SELECT Id FROM sbaa__Approver__c WHERE Name = 'Credit Control' LIMIT 1];
List<sbaa__ApprovalRule__c> upd = new List<sbaa__ApprovalRule__c>();
for (sbaa__ApprovalRule__c r : [SELECT Id, Name, sbaa__Active__c, sbaa__Approver__c, sbaa__Approver__r.Name FROM sbaa__ApprovalRule__c
                                WHERE Name LIKE '% - Amendments' OR sbaa__Approver__r.Name = 'Finance Approvers - Quote']) {
    if (r.Name.endsWith(' - Amendments')) {
        r.sbaa__Active__c = true; upd.add(r);
    } else if (r.sbaa__Approver__r.Name == 'Finance Approvers - Quote') {
        r.sbaa__Approver__c = core.Id; upd.add(r);
    }
}
update upd;
for (sbaa__ApprovalRule__c r : [SELECT Name, sbaa__Active__c, sbaa__Approver__r.Name FROM sbaa__ApprovalRule__c
                                WHERE Name LIKE '% - Amendments' OR Name IN ('LBR - Quote: Finance Terms','LBR - Quote: Finance Problem and Bad Debtor','LBR - Quote: Big Deal >= 50K','ALM - Quote: Bad Debtor','ALM - Quote: Special Terms','ALM - Quote: Credit Card >=15k') ORDER BY Name]) {
    System.debug('RULE ' + r.Name + ' active=' + r.sbaa__Active__c + ' -> ' + r.sbaa__Approver__r.Name);
}
