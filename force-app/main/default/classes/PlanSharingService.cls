/**
 * Maintains plan-team-based sharing (architecture 8): every Plan_Team_Member__c user
 * gets Edit access to the parent Account_Plan__c via the Plan_Team_Access__c row cause.
 * Account_Plan__c OWD is Public Read Only; this elevates team members to Edit.
 */
public with sharing class PlanSharingService {

    public static void recalculate(Set<Id> planIds) {
        if (planIds == null || planIds.isEmpty()) {
            return;
        }

        // Clear existing team shares for these plans, then rebuild from current membership.
        delete [
            SELECT Id FROM Account_Plan__Share
            WHERE ParentId IN :planIds
            AND RowCause = :Schema.Account_Plan__Share.RowCause.Plan_Team_Access__c
        ];

        Map<Id, Id> ownerByPlan = new Map<Id, Id>();
        for (Account_Plan__c p : [SELECT Id, OwnerId FROM Account_Plan__c WHERE Id IN :planIds]) {
            ownerByPlan.put(p.Id, p.OwnerId);
        }

        Set<String> seen = new Set<String>();
        List<Account_Plan__Share> shares = new List<Account_Plan__Share>();
        for (Plan_Team_Member__c tm : [
            SELECT Account_Plan__c, User__c FROM Plan_Team_Member__c
            WHERE Account_Plan__c IN :planIds AND User__c != null
        ]) {
            // Cannot share with the record owner.
            if (tm.User__c == ownerByPlan.get(tm.Account_Plan__c)) {
                continue;
            }
            String key = tm.Account_Plan__c + '-' + tm.User__c;
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);

            Account_Plan__Share sh = new Account_Plan__Share();
            sh.ParentId = tm.Account_Plan__c;
            sh.UserOrGroupId = tm.User__c;
            sh.AccessLevel = 'Edit';
            sh.RowCause = Schema.Account_Plan__Share.RowCause.Plan_Team_Access__c;
            shares.add(sh);
        }

        if (!shares.isEmpty()) {
            Database.insert(shares, false);
        }
    }
}
