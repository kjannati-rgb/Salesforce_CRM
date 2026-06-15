/*
 * Seed stakeholders + objectives onto the demo Account Plans.
 * Run AFTER seed_account_plans.apex.
 *   sf apex run --file scripts/seed/seed_stakeholders_objectives.apex --target-org KJDEV
 * Idempotent: clears existing children on the two demo plans, then re-creates.
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
delete [SELECT Id FROM Plan_Stakeholder__c WHERE Account_Plan__c IN :planIds];
delete [SELECT Id FROM Plan_Objective__c   WHERE Account_Plan__c IN :planIds];

Map<String, Id> fam = new Map<String, Id>();
for (Plan_Product_Family__c f : [SELECT Id, Name FROM Plan_Product_Family__c]) {
    fam.put(f.Name, f.Id);
}

// --- Stakeholders (spec = 'Name|Role|Influence|Sentiment|BuyingCenter') ---
Map<Id, List<String>> stk = new Map<Id, List<String>>{
    law => new List<String>{
        'Alicia Reyes|General Counsel, London|High|Champion|London',
        'Tom Webb|Practice Head, Disputes|High|Supporter|London',
        'S. Patel|Knowledge Lead, Manchester|Medium|Neutral|Manchester',
        'M. Dubois|Procurement, New York|Medium|Detractor|New York',
        'K. Olsen|Library Services|Low|Supporter|London'
    },
    corp => new List<String>{
        'Sarah Nweze|Group General Counsel|High|Neutral|Group Legal',
        'James Cole|Head of Commercial|High|Champion|Commercial & Disputes',
        'Priya Anand|Head of Regulatory|Medium|Supporter|Regulatory & Competition',
        'Olaf Berg|Legal Ops, EU|Medium|Detractor|Demo Corp EU',
        'Lena Fischer|Knowledge Manager|Low|Neutral|Group Legal'
    }
};
List<Plan_Stakeholder__c> stakeholders = new List<Plan_Stakeholder__c>();
for (Id planId : stk.keySet()) {
    for (String spec : stk.get(planId)) {
        List<String> p = spec.split('\\|');
        stakeholders.add(new Plan_Stakeholder__c(
            Account_Plan__c = planId, Stakeholder_Name__c = p[0], Role__c = p[1],
            Influence__c = p[2], Sentiment__c = p[3], Buying_Center__c = p[4]));
    }
}
insert stakeholders;

// --- Objectives (spec = 'Title|Status|Progress|Target|DueYYYY-MM-DD|FamilyOrNone') ---
Map<Id, List<String>> obj = new Map<Id, List<String>>{
    law => new List<String>{
        'Land ALM Intelligence - EMEA|In_Progress|40|280000|2026-09-30|Lexology Intelligence',
        'Win back Advertising - London|At_Risk|15|45000|2026-08-31|Advertising',
        'Lift seat penetration to T1 median|In_Progress|62|0|2026-12-31|none'
    },
    corp => new List<String>{
        'Convert Intelligence white space - UK|In_Progress|25|320000|2026-10-31|Lexology Intelligence',
        'Counsel penetration to T2 median|In_Progress|54|0|2026-12-31|none',
        'Secure new-GC exec sponsorship|At_Risk|30|0|2026-09-15|none'
    }
};
List<Plan_Objective__c> objectives = new List<Plan_Objective__c>();
for (Id planId : obj.keySet()) {
    for (String spec : obj.get(planId)) {
        List<String> p = spec.split('\\|');
        objectives.add(new Plan_Objective__c(
            Account_Plan__c = planId, Name = p[0], Status__c = p[1],
            Progress_Pct__c = Decimal.valueOf(p[2]),
            Target_Amount__c = Decimal.valueOf(p[3]),
            Due_Date__c = Date.valueOf(p[4]),
            Linked_Family__c = (p[5] == 'none' ? null : fam.get(p[5]))));
    }
}
insert objectives;

System.debug('Seeded ' + stakeholders.size() + ' stakeholders and ' + objectives.size() + ' objectives.');
