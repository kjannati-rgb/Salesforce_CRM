/*
 * Seed Key Signals + Plan Team onto the demo Account Plans.
 * Run AFTER seed_account_plans.apex.
 *   sf apex run --file scripts/seed/seed_signals_team.apex --target-org KJDEV
 * Idempotent: clears existing signals/team on the two demo plans, then re-creates.
 */

Map<String, Id> plan = new Map<String, Id>();
for (Account_Plan__c p : [SELECT Id, Name FROM Account_Plan__c
                          WHERE Name IN ('Globex Legal (DEMO) - Account Plan', 'Demo Corp Alpha - Legal & Compliance')]) {
    plan.put(p.Name, p.Id);
}
if (plan.isEmpty()) {
    System.debug('No demo plans found - run seed_account_plans.apex first.');
    return;
}
Id law  = plan.get('Globex Legal (DEMO) - Account Plan');
Id corp = plan.get('Demo Corp Alpha - Legal & Compliance');
Set<Id> planIds = new Set<Id>(plan.values());

delete [SELECT Id FROM Plan_Signal__c WHERE Account_Plan__c IN :planIds];
delete [SELECT Id FROM Plan_Team_Member__c WHERE Account_Plan__c IN :planIds];

// --- Signals (spec = 'Type|Severity|Source|Summary|RecommendedAction') ---
Map<Id, List<String>> sig = new Map<Id, List<String>>{
    law => new List<String>{
        'Risk|High|CPQ|Renewal window - ALM Intelligence: GBP 420K ends in 74 days (London)|Open renewal play; assign AE',
        'Relationship|Medium|Contact history|Champion job-change: S. Patel moved roles (Manchester)|Re-map Manchester relationships',
        'Expansion|Medium|Whitespace_Cell|White-space threshold crossed: Lexology Intelligence gap GBP 140K|Draft opportunity',
        'Intent|Medium|ZoomInfo|Intent spike on "legal AI" (DC office)|Prioritise outbound'
    },
    corp => new List<String>{
        'Risk|Medium|CPQ|Renewal window - Lexology PRO: GBP 48K ends in 30 days (IP & Privacy)|Open renewal play',
        'Churn|High|Data Cloud|Usage dip: Intelligence trial -38% sessions vs baseline|Schedule success review',
        'Intent|High|Clay|Intent spike on "competition law" (Regulatory team)|Outbound to Regulatory',
        'Relationship|Medium|Contact history|New GC appointed (Group Legal)|Secure exec sponsorship'
    }
};
List<Plan_Signal__c> signals = new List<Plan_Signal__c>();
for (Id planId : sig.keySet()) {
    Integer age = 1;
    for (String spec : sig.get(planId)) {
        List<String> p = spec.split('\\|');
        signals.add(new Plan_Signal__c(
            Account_Plan__c = planId, Signal_Type__c = p[0], Severity__c = p[1], Source__c = p[2],
            Summary__c = p[3], Recommended_Action__c = p[4], Status__c = 'Open',
            Detected_Date__c = Date.today().addDays(-age)));
        age += 3;
    }
}
insert signals;

// --- Team (current user as Plan Lead; spare active users fill the other lanes) ---
Map<String, Id> fam = new Map<String, Id>();
for (Plan_Product_Family__c f : [SELECT Id, Name FROM Plan_Product_Family__c]) fam.put(f.Name, f.Id);

Id me = UserInfo.getUserId();
List<Id> spares = new List<Id>();
for (User u : [SELECT Id FROM User WHERE IsActive = true AND Id != :me LIMIT 4]) spares.add(u.Id);

List<Plan_Team_Member__c> team = new List<Plan_Team_Member__c>();
team.add(new Plan_Team_Member__c(Account_Plan__c = law,  User__c = me, Plan_Role__c = 'Plan_Lead'));
team.add(new Plan_Team_Member__c(Account_Plan__c = corp, User__c = me, Plan_Role__c = 'Plan_Lead'));
if (spares.size() >= 1) {
    team.add(new Plan_Team_Member__c(Account_Plan__c = law,  User__c = spares[0], Plan_Role__c = 'Lane_Owner', Product_Family__c = fam.get('Lexology Intelligence')));
    team.add(new Plan_Team_Member__c(Account_Plan__c = corp, User__c = spares[0], Plan_Role__c = 'Lane_Owner', Product_Family__c = fam.get('Lexology Intelligence')));
}
if (spares.size() >= 2) {
    team.add(new Plan_Team_Member__c(Account_Plan__c = law,  User__c = spares[1], Plan_Role__c = 'SDR'));
    team.add(new Plan_Team_Member__c(Account_Plan__c = corp, User__c = spares[1], Plan_Role__c = 'Contributor'));
}
insert team;  // PlanTeamMemberTrigger recalculates Plan_Team_Access__c sharing

System.debug('Seeded ' + signals.size() + ' signals and ' + team.size() + ' team members.');
