/**
 * Centellic Payment Term Extension Process - AA setup, part 1 of 2 (SETUP OBJECTS ONLY)
 * Run via: sf apex run --file scripts/aa_setup_1_groups.apex -o <orgAlias>
 *
 * Split from part 2 because Group/GroupMember are setup objects and mixing them with
 * sbaa__* DML throws MIXED_DML_OPERATION.
 *
 * Creates (idempotent):
 *   1. Public Group "Financial Control Director" with Lina Patel as member (all orgs)
 *   2. Sandbox only: Public Group "Credit Control" with Samantha Law as member
 *      (prod already has group 00GPx00000Jh8NZ - untouched there)
 */

// ---- Financial Control Director group ----
Group fcGroup;
List<Group> existing = [SELECT Id FROM Group WHERE DeveloperName = 'Financial_Control_Director' AND Type = 'Regular' LIMIT 1];
if (existing.isEmpty()) {
    fcGroup = new Group(Name = 'Financial Control Director', DeveloperName = 'Financial_Control_Director', Type = 'Regular');
    insert fcGroup;
} else {
    fcGroup = existing[0];
}

User lina = [SELECT Id FROM User WHERE Name = 'Lina Patel' AND IsActive = true LIMIT 1];
if ([SELECT Id FROM GroupMember WHERE GroupId = :fcGroup.Id AND UserOrGroupId = :lina.Id].isEmpty()) {
    insert new GroupMember(GroupId = fcGroup.Id, UserOrGroupId = lina.Id);
}
System.debug('Financial Control Director group: ' + fcGroup.Id);

// ---- Credit Control group: sandbox only (prod group already exists) ----
if ([SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
        && [SELECT Id FROM sbaa__Approver__c WHERE Name = 'Credit Control' LIMIT 1].isEmpty()) {
    Group ccGroup;
    List<Group> ccGroups = [SELECT Id FROM Group WHERE DeveloperName = 'Credit_Control' AND Type = 'Regular' LIMIT 1];
    if (ccGroups.isEmpty()) {
        ccGroup = new Group(Name = 'Credit Control', DeveloperName = 'Credit_Control', Type = 'Regular');
        insert ccGroup;
    } else {
        ccGroup = ccGroups[0];
    }
    User samantha = [SELECT Id FROM User WHERE Name = 'Samantha Law' AND IsActive = true LIMIT 1];
    if ([SELECT Id FROM GroupMember WHERE GroupId = :ccGroup.Id AND UserOrGroupId = :samantha.Id].isEmpty()) {
        insert new GroupMember(GroupId = ccGroup.Id, UserOrGroupId = samantha.Id);
    }
    System.debug('Sandbox Credit Control group: ' + ccGroup.Id);
}
