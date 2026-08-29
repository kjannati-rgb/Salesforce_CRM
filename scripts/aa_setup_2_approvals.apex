/**
 * Centellic Payment Term Extension Process - AA setup, part 2 of 2 (sbaa records)
 * Run via: sf apex run --file scripts/aa_setup_2_approvals.apex -o <orgAlias>
 * PREREQUISITE: run aa_setup_1_groups.apex first (separate transaction - MIXED_DML).
 *
 * Creates (idempotent - checks for existing records by Name first):
 *   1. sbaa__Approver__c "Director of Financial Control" -> Financial Control Director group
 *   2. Sandbox only: sbaa__Approver__c "Credit Control" -> sandbox Credit Control group
 *      (prod already has this approver - queried, never created there)
 *   3. sbaa__ApprovalChain__c "Quote: Payment Terms"
 *   4. Two chained sbaa__ApprovalRule__c records (created INACTIVE - activate after testing):
 *        Step 1: Credit Control review           Step 2: Director of Financial Control
 *   5. One sbaa__ApprovalCondition__c per rule: Payment_Terms_Days__c > 30
 *
 * NOTE: the under-10k-ACV block is enforced by validation rule, so the approval
 * condition only needs the >30 days test. Anything reaching approval is >= GBP 7,500 ACV.
 */

Group fcGroup = [SELECT Id FROM Group WHERE DeveloperName = 'Financial_Control_Director' AND Type = 'Regular' LIMIT 1];

// ---- Approver records ----
sbaa__Approver__c fcApprover;
List<sbaa__Approver__c> approvers = [SELECT Id FROM sbaa__Approver__c WHERE Name = 'Director of Financial Control' LIMIT 1];
if (approvers.isEmpty()) {
    fcApprover = new sbaa__Approver__c(Name = 'Director of Financial Control', sbaa__GroupId__c = fcGroup.Id);
    insert fcApprover;
} else {
    fcApprover = approvers[0];
}

// Prod has an existing "Credit Control" approver (query-only there). Sandboxes have no
// sbaa data seeded, so create the approver from the part-1 sandbox group.
sbaa__Approver__c creditControl;
List<sbaa__Approver__c> ccApprovers = [SELECT Id FROM sbaa__Approver__c WHERE Name = 'Credit Control' LIMIT 1];
if (!ccApprovers.isEmpty()) {
    creditControl = ccApprovers[0];
} else if ([SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {
    Group ccGroup = [SELECT Id FROM Group WHERE DeveloperName = 'Credit_Control' AND Type = 'Regular' LIMIT 1];
    creditControl = new sbaa__Approver__c(Name = 'Credit Control', sbaa__GroupId__c = ccGroup.Id);
    insert creditControl;
} else {
    throw new QueryException('Credit Control approver not found in production - aborting, do not auto-create in prod.');
}

// ---- Approval chain ----
sbaa__ApprovalChain__c chain;
List<sbaa__ApprovalChain__c> chains = [SELECT Id FROM sbaa__ApprovalChain__c WHERE Name = 'Quote: Payment Terms' LIMIT 1];
if (chains.isEmpty()) {
    chain = new sbaa__ApprovalChain__c(Name = 'Quote: Payment Terms', sbaa__TargetObject__c = 'SBQQ__Quote__c');
    insert chain;
} else {
    chain = chains[0];
}

// ---- Approval rules (inactive until tested/approved for go-live) ----
Map<String, sbaa__ApprovalRule__c> rules = new Map<String, sbaa__ApprovalRule__c>();
for (sbaa__ApprovalRule__c r : [SELECT Id, Name FROM sbaa__ApprovalRule__c WHERE sbaa__ApprovalChain__c = :chain.Id]) {
    rules.put(r.Name, r);
}

List<sbaa__ApprovalRule__c> toInsert = new List<sbaa__ApprovalRule__c>();
if (!rules.containsKey('Centellic - Quote: Payment Terms > 30 Days - Credit Control')) {
    toInsert.add(new sbaa__ApprovalRule__c(
        Name = 'Centellic - Quote: Payment Terms > 30 Days - Credit Control',
        sbaa__TargetObject__c = 'SBQQ__Quote__c',
        sbaa__ApprovalChain__c = chain.Id,
        sbaa__ApprovalStep__c = 1,
        sbaa__Approver__c = creditControl.Id,
        sbaa__ConditionsMet__c = 'All',
        sbaa__Active__c = false
    ));
}
if (!rules.containsKey('Centellic - Quote: Payment Terms > 30 Days - Financial Control Director')) {
    toInsert.add(new sbaa__ApprovalRule__c(
        Name = 'Centellic - Quote: Payment Terms > 30 Days - Financial Control Director',
        sbaa__TargetObject__c = 'SBQQ__Quote__c',
        sbaa__ApprovalChain__c = chain.Id,
        sbaa__ApprovalStep__c = 2,
        sbaa__Approver__c = fcApprover.Id,
        sbaa__ConditionsMet__c = 'All',
        sbaa__Active__c = false
    ));
}
insert toInsert;

// ---- Conditions: Payment_Terms_Days__c > 30 on each rule ----
Set<Id> rulesWithConds = new Set<Id>();
for (sbaa__ApprovalCondition__c c : [SELECT sbaa__ApprovalRule__c FROM sbaa__ApprovalCondition__c
                                     WHERE sbaa__ApprovalRule__r.sbaa__ApprovalChain__c = :chain.Id]) {
    rulesWithConds.add(c.sbaa__ApprovalRule__c);
}
List<sbaa__ApprovalCondition__c> conds = new List<sbaa__ApprovalCondition__c>();
for (sbaa__ApprovalRule__c r : [SELECT Id FROM sbaa__ApprovalRule__c WHERE sbaa__ApprovalChain__c = :chain.Id]) {
    if (!rulesWithConds.contains(r.Id)) {
        conds.add(new sbaa__ApprovalCondition__c(
            sbaa__ApprovalRule__c = r.Id,
            sbaa__TestedField__c = 'Payment_Terms_Days__c',
            sbaa__Operator__c = 'greater than',
            sbaa__FilterValue__c = '30',
            sbaa__FilterType__c = 'Value',
            sbaa__Index__c = 1
        ));
    }
}
insert conds;

System.debug('AA setup complete. Chain: ' + chain.Id + ' | Rules created this run: ' + toInsert.size());
