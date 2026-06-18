/**
 * After an account MERGE, restore the single-holder invariant on the surviving
 * master. Merge reparents the losing accounts' AccountTeamMember rows onto the
 * master without firing the AccountTeamMember trigger, so duplicate single-holder
 * roles (and a stale mirror) can slip through. The deleted (losing) records carry
 * MasterRecordId, which lets us detect the merge and hand the master(s) to
 * AccountTeamMergeResolver.
 *
 * Scoped to AFTER DELETE only and does its work on AccountTeamMember (a different
 * object), so it stays isolated from this org's other Account triggers.
 */
trigger AccountTeamMergeTrigger on Account (after delete) {
    Set<Id> masterIds = new Set<Id>();
    for (Account a : Trigger.old) {
        if (a.MasterRecordId != null) {
            masterIds.add(a.MasterRecordId);
        }
    }
    if (!masterIds.isEmpty()) {
        AccountTeamMergeResolver.resolve(masterIds);
    }
}
