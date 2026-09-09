// Finance approver split - step 4: retire the old "Finance Approvers - Quote" group + sbaa approver.
// Idempotent. Refuses to run while a LIVE request is still assigned to the old group.
// Keeps both records (12,700+ approval history rows reference the approver by lookup and the group by text id):
//   - sbaa__Approver__c renamed "... (retired Sep 2026)"
//   - public Group renamed "zz Retired - Finance Approvers - Quote", all members removed (no more notifications)
// Delete the group manually after 30 quiet days if nothing else turns out to reference it.
// Pre-req (done separately, metadata): the two quote recall email alerts now address ALM_Credit_Control.
// Run: sf apex run -o PROD -f scripts/finance_split_4_retire_old_group.apex   (unset HTTP_PROXY HTTPS_PROXY first)

Id oldGroupId = '00G4L000001Y1ymUAC';
String oldGroup15 = String.valueOf(oldGroupId).left(15);

// 1. Guard: a live request = Requested/Assigned approval whose quote is still under review.
List<SBAA__Approval__c> live = [
    SELECT Id, Name, Quote__r.Name, Quote__r.SBQQ__Status__c
    FROM SBAA__Approval__c
    WHERE sbaa__Approver__r.sbaa__GroupId__c IN :new List<String>{ oldGroup15, String.valueOf(oldGroupId) }
      AND sbaa__Status__c IN ('Requested', 'Assigned')
      AND Quote__r.SBQQ__Status__c IN ('In Review', 'Pending', 'Pending Approval')
];
if (!live.isEmpty()) {
    for (SBAA__Approval__c a : live) System.debug('LIVE: ' + a.Name + ' on ' + a.Quote__r.Name + ' (' + a.Quote__r.SBQQ__Status__c + ')');
    throw new HandledException('ABORT: ' + live.size() + ' live request(s) still on the old group - retry after they resolve.');
}

// 2. Guard: no active rule may still point at the old approver.
Integer rules = [SELECT COUNT() FROM sbaa__ApprovalRule__c
                 WHERE sbaa__Approver__r.sbaa__GroupId__c IN :new List<String>{ oldGroup15, String.valueOf(oldGroupId) }];
if (rules > 0) throw new HandledException('ABORT: ' + rules + ' approval rule(s) still use the old approver.');

// 3. Rename the sbaa approver (history keeps pointing at it).
List<sbaa__Approver__c> apps = [SELECT Id, Name FROM sbaa__Approver__c
                                WHERE sbaa__GroupId__c IN :new List<String>{ oldGroup15, String.valueOf(oldGroupId) }];
for (sbaa__Approver__c ap : apps) {
    if (!ap.Name.contains('(retired')) { ap.Name = 'Finance Approvers - Quote (retired Sep 2026)'; }
}
update apps;

// 4. Empty and rename the public group.
List<GroupMember> members = [SELECT Id FROM GroupMember WHERE GroupId = :oldGroupId];
delete members;
Group g = [SELECT Id, Name FROM Group WHERE Id = :oldGroupId];
if (!g.Name.startsWith('zz Retired')) { g.Name = 'zz Retired - Finance Approvers - Quote'; update g; }

System.debug('DONE: approver renamed (' + apps.size() + '), ' + members.size() + ' members removed, group renamed to "' + g.Name + '".');
