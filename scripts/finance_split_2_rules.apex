/**
 * Finance approver split - part 2 of 3 (sbaa records; run AFTER part 1 - MIXED_DML split)
 * Run: sf apex run --file scripts/finance_split_2_rules.apex -o <org>
 * Idempotent. For each ACTIVE legacy finance rule in RULES:
 *   - adds condition  SBQQ__Type__c NOT EQUALS Amendment  (next index in the rule's own numbering;
 *     rules with Custom logic get "(old) AND n")
 *   - creates an INACTIVE clone "<name> - Amendments" on the same chain/step, all conditions copied,
 *     the type condition flipped to EQUALS Amendment, approver = "Finance - Amendments"
 * Also creates the "Finance - Amendments" sbaa approver (-> Finance_Amendments group) if missing.
 * Part 3 activates the clones and repoints the LBR originals to the core "Credit Control" approver.
 * The extended-payment-terms chain is deliberately NOT split (credit decision -> core always).
 */
Set<String> RULES = new Set<String>{
    'LBR - Quote: Finance Terms', 'LBR - Quote: Finance Problem and Bad Debtor', 'LBR - Quote: Big Deal >= 50K',
    'ALM - Quote: Bad Debtor', 'ALM - Quote: Special Terms', 'ALM - Quote: Credit Card >=15k'
};
Group amendGroup = [SELECT Id FROM Group WHERE DeveloperName = 'Finance_Amendments' AND Type = 'Regular' LIMIT 1];
sbaa__Approver__c amendApprover;
List<sbaa__Approver__c> aps = [SELECT Id FROM sbaa__Approver__c WHERE Name = 'Finance - Amendments' LIMIT 1];
if (aps.isEmpty()) {
    amendApprover = new sbaa__Approver__c(Name = 'Finance - Amendments', sbaa__GroupId__c = amendGroup.Id);
    insert amendApprover;
} else {
    amendApprover = aps[0];
}

List<sbaa__ApprovalRule__c> originals = [
    SELECT Id, Name, sbaa__TargetObject__c, sbaa__ApprovalChain__c, sbaa__ApprovalStep__c, sbaa__Approver__c,
           sbaa__ConditionsMet__c, sbaa__AdvancedCondition__c, sbaa__Active__c,
           sbaa__ApprovalTemplate__c, sbaa__RejectionTemplate__c, sbaa__RequestTemplate__c, sbaa__RecallTemplate__c
    FROM sbaa__ApprovalRule__c WHERE Name IN :RULES AND sbaa__Active__c = true];

Map<Id, List<sbaa__ApprovalCondition__c>> condsByRule = new Map<Id, List<sbaa__ApprovalCondition__c>>();
for (sbaa__ApprovalCondition__c c : [SELECT Id, sbaa__ApprovalRule__c, sbaa__Index__c, sbaa__TestedField__c, sbaa__Operator__c, sbaa__FilterValue__c, sbaa__FilterType__c, sbaa__TestedVariable__c
                                     FROM sbaa__ApprovalCondition__c WHERE sbaa__ApprovalRule__c IN :originals]) {
    if (!condsByRule.containsKey(c.sbaa__ApprovalRule__c)) condsByRule.put(c.sbaa__ApprovalRule__c, new List<sbaa__ApprovalCondition__c>());
    condsByRule.get(c.sbaa__ApprovalRule__c).add(c);
}
Set<String> existingClones = new Set<String>();
for (sbaa__ApprovalRule__c r : [SELECT Name FROM sbaa__ApprovalRule__c WHERE Name LIKE '% - Amendments']) existingClones.add(r.Name);

List<sbaa__ApprovalCondition__c> newConds = new List<sbaa__ApprovalCondition__c>();
List<sbaa__ApprovalRule__c> rulesToUpdate = new List<sbaa__ApprovalRule__c>();
List<sbaa__ApprovalRule__c> clones = new List<sbaa__ApprovalRule__c>();
Map<Id, sbaa__ApprovalRule__c> cloneSource = new Map<Id, sbaa__ApprovalRule__c>();

for (sbaa__ApprovalRule__c r : originals) {
    List<sbaa__ApprovalCondition__c> cs = condsByRule.containsKey(r.Id) ? condsByRule.get(r.Id) : new List<sbaa__ApprovalCondition__c>();
    Boolean alreadyTyped = false; Decimal maxIdx = 0; Boolean tens = false;
    for (sbaa__ApprovalCondition__c c : cs) {
        if (c.sbaa__TestedField__c == 'SBQQ__Type__c') alreadyTyped = true;
        if (c.sbaa__Index__c != null && c.sbaa__Index__c > maxIdx) maxIdx = c.sbaa__Index__c;
        if (c.sbaa__Index__c != null && c.sbaa__Index__c >= 10) tens = true;
    }
    Decimal newIdx = tens ? (Math.floor(maxIdx / 10) * 10 + 10) : (maxIdx + 1);
    if (!alreadyTyped) {
        newConds.add(new sbaa__ApprovalCondition__c(sbaa__ApprovalRule__c = r.Id, sbaa__Index__c = newIdx,
            sbaa__TestedField__c = 'SBQQ__Type__c', sbaa__Operator__c = 'not equals', sbaa__FilterValue__c = 'Amendment', sbaa__FilterType__c = 'Value'));
        if (r.sbaa__ConditionsMet__c == 'Custom') {
            r.sbaa__AdvancedCondition__c = '(' + r.sbaa__AdvancedCondition__c + ') AND ' + String.valueOf(newIdx.intValue());
            rulesToUpdate.add(r);
        }
    }
    String cloneName = r.Name + ' - Amendments';
    if (!existingClones.contains(cloneName)) {
        sbaa__ApprovalRule__c cl = r.clone(false, true, false, false);
        cl.Name = cloneName;
        cl.sbaa__Active__c = false;
        cl.sbaa__Approver__c = amendApprover.Id;
        cl.sbaa__ConditionsMet__c = 'All';      // AA validation: Custom logic only allowed once conditions exist
        cl.sbaa__AdvancedCondition__c = null;
        clones.add(cl);
        cloneSource.put(r.Id, cl);
    }
}
insert newConds;
update rulesToUpdate;   // logic references the new index - must exist first
insert clones;

// clone conditions (originals' + the new type condition, flipped to EQUALS on the clone)
List<sbaa__ApprovalCondition__c> cloneConds = new List<sbaa__ApprovalCondition__c>();
for (sbaa__ApprovalCondition__c c : [SELECT sbaa__ApprovalRule__c, sbaa__Index__c, sbaa__TestedField__c, sbaa__Operator__c, sbaa__FilterValue__c, sbaa__FilterType__c, sbaa__TestedVariable__c
                                     FROM sbaa__ApprovalCondition__c WHERE sbaa__ApprovalRule__c IN :cloneSource.keySet()]) {
    sbaa__ApprovalRule__c cl = cloneSource.get(c.sbaa__ApprovalRule__c);
    sbaa__ApprovalCondition__c cc = c.clone(false, true, false, false);
    cc.sbaa__ApprovalRule__c = cl.Id;
    if (cc.sbaa__TestedField__c == 'SBQQ__Type__c') cc.sbaa__Operator__c = 'equals';
    cloneConds.add(cc);
}
insert cloneConds;
List<sbaa__ApprovalRule__c> restoreLogic = new List<sbaa__ApprovalRule__c>();
for (sbaa__ApprovalRule__c r : originals) {
    if (r.sbaa__ConditionsMet__c == 'Custom' && cloneSource.containsKey(r.Id)) {
        sbaa__ApprovalRule__c cl = cloneSource.get(r.Id);
        restoreLogic.add(new sbaa__ApprovalRule__c(Id = cl.Id, sbaa__ConditionsMet__c = 'Custom', sbaa__AdvancedCondition__c = r.sbaa__AdvancedCondition__c));
    }
}
update restoreLogic;
System.debug('SPLIT: type-conditions added=' + newConds.size() + ' custom-logic extended=' + rulesToUpdate.size() + ' clones created=' + clones.size() + ' clone conditions=' + cloneConds.size() + ' | amendments approver=' + amendApprover.Id);
