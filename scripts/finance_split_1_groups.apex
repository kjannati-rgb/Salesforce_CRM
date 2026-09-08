/**
 * Finance approver split - part 1 of 3 (SETUP OBJECTS ONLY; MIXED_DML split)
 * Run: sf apex run --file scripts/finance_split_1_groups.apex -o <org>
 * Idempotent. Creates/aligns:
 *   - "Credit Control" core group: Samantha Law, Leslie Perry, Candice Goodpaster, Rahul Vadgama (UK backup)
 *       prod: the existing "ALM - Credit Control" group 00GPx00000Jh8NZ is RENAMED "Credit Control"
 *       (Id unchanged -> approver a5UPx0000001E49MAE keeps working)
 *   - "Finance - Amendments" group: Kevin Daud, Chloe Orrin, Willie Guerrero, Grace Walther, Sherry Costello
 * Never removes members - removals are a deliberate admin step.
 */
Map<String, Id> userByName = new Map<String, Id>();
for (User u : [SELECT Id, Name FROM User WHERE IsActive = true AND Name IN ('Samantha Law','Leslie Perry','Candice Goodpaster','Rahul Vadgama','Kevin Daud','Chloe Orrin','Willie Guerrero','Grace Walther','Sherry Costello')]) {
    userByName.put(u.Name, u.Id);
}

// ---- core group ----
Group core;
List<Group> cores = [SELECT Id, Name FROM Group WHERE Type = 'Regular' AND DeveloperName IN ('ALM_Credit_Control','Credit_Control') ORDER BY DeveloperName LIMIT 1];
if (cores.isEmpty()) {
    core = new Group(Name = 'Credit Control', DeveloperName = 'Credit_Control', Type = 'Regular');
    insert core;
} else {
    core = cores[0];
    if (core.Name != 'Credit Control') { core.Name = 'Credit Control'; update core; }
}

// ---- amendments group ----
Group amend;
List<Group> amends = [SELECT Id FROM Group WHERE Type = 'Regular' AND DeveloperName = 'Finance_Amendments' LIMIT 1];
if (amends.isEmpty()) {
    amend = new Group(Name = 'Finance - Amendments', DeveloperName = 'Finance_Amendments', Type = 'Regular');
    insert amend;
} else {
    amend = amends[0];
}

// ---- membership (add missing only) ----
Map<Id, Set<String>> want = new Map<Id, Set<String>>{
    core.Id  => new Set<String>{'Samantha Law','Leslie Perry','Candice Goodpaster','Rahul Vadgama'},
    amend.Id => new Set<String>{'Kevin Daud','Chloe Orrin','Willie Guerrero','Grace Walther','Sherry Costello'}
};
Set<String> have = new Set<String>();
for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :want.keySet()]) {
    have.add(gm.GroupId + ':' + gm.UserOrGroupId);
}
List<GroupMember> toAdd = new List<GroupMember>();
for (Id gid : want.keySet()) {
    for (String n : want.get(gid)) {
        Id uid = userByName.get(n);
        if (uid == null) { System.debug('SKIP (no active user in this org): ' + n); continue; }
        if (!have.contains(gid + ':' + uid)) toAdd.add(new GroupMember(GroupId = gid, UserOrGroupId = uid));
    }
}
insert toAdd;
System.debug('core group=' + core.Id + ' amendments group=' + amend.Id + ' | members added: ' + toAdd.size());
