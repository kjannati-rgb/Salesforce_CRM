/*
 * Seed demo Account Plans for KJDEV so the White-Space Matrix renders like the prototype.
 * Idempotent: removes prior demo plans (master-detail cascade-deletes their cells), then re-creates.
 * Run with:  sf apex run --file scripts/seed/seed_account_plans.apex --target-org KJDEV
 */

// 1) Product family columns (create any that are missing)
Map<String, Plan_Product_Family__c> wanted = new Map<String, Plan_Product_Family__c>{
    'Lexology PRO'          => new Plan_Product_Family__c(Name='Lexology PRO',          Family_Type__c='Recurring',     Relevant_Law_Firm__c=true,  Relevant_Corporate__c=true,  Sort_Order__c=1),
    'Specialist Platforms'  => new Plan_Product_Family__c(Name='Specialist Platforms',  Family_Type__c='Recurring',     Relevant_Law_Firm__c=true,  Relevant_Corporate__c=true,  Sort_Order__c=2),
    'Lexology Intelligence' => new Plan_Product_Family__c(Name='Lexology Intelligence', Family_Type__c='Recurring',     Relevant_Law_Firm__c=true,  Relevant_Corporate__c=true,  Sort_Order__c=3),
    'ALM Subs / IS'         => new Plan_Product_Family__c(Name='ALM Subs / IS',         Family_Type__c='Recurring',     Relevant_Law_Firm__c=true,  Relevant_Corporate__c=true,  Sort_Order__c=4),
    'Events & Sponsorship'  => new Plan_Product_Family__c(Name='Events & Sponsorship',  Family_Type__c='Transactional', Relevant_Law_Firm__c=true,  Relevant_Corporate__c=true,  Sort_Order__c=5),
    'Advertising'           => new Plan_Product_Family__c(Name='Advertising',           Family_Type__c='Transactional', Relevant_Law_Firm__c=true,  Relevant_Corporate__c=false, Sort_Order__c=6)
};
Map<String, Id> famId = new Map<String, Id>();
for (Plan_Product_Family__c f : [SELECT Id, Name FROM Plan_Product_Family__c WHERE Name IN :wanted.keySet()]) {
    famId.put(f.Name, f.Id);
}
List<Plan_Product_Family__c> newFams = new List<Plan_Product_Family__c>();
for (String n : wanted.keySet()) {
    if (!famId.containsKey(n)) newFams.add(wanted.get(n));
}
if (!newFams.isEmpty()) insert newFams;
for (Plan_Product_Family__c f : newFams) famId.put(f.Name, f.Id);

// 2) Remove prior demo plans (cascades to cells)
delete [SELECT Id FROM Account_Plan__c WHERE Name IN ('Latham & Watkins LLP', 'Vodafone Group plc - Legal & Compliance')];

// 3) Record types
Id lawRt  = Schema.SObjectType.Account_Plan__c.getRecordTypeInfosByDeveloperName().get('Law_Firm').getRecordTypeId();
Id corpRt = Schema.SObjectType.Account_Plan__c.getRecordTypeInfosByDeveloperName().get('Corporate').getRecordTypeId();

// 4) Plans
Account_Plan__c law = new Account_Plan__c(
    Name='Latham & Watkins LLP', RecordTypeId=lawRt, Plan_Tier__c='T1', Deal_Model__c='Enterprise',
    Plan_Status__c='Active', SoW_Denominator__c=312, Family_Coverage_Pct__c=54, Seat_Penetration_Pct__c=38,
    Review_Cadence__c='Quarterly', Next_Review_Date__c=Date.newInstance(2026,7,31),
    Strengths__c='Deep Lexology PRO adoption in US offices',
    Weaknesses__c='Zero ALM footprint in EMEA',
    Opportunities__c='Intelligence cross-sell across the 312-attorney London base',
    Threats__c='Competitor renewal pressure in Paris');
Account_Plan__c corp = new Account_Plan__c(
    Name='Vodafone Group plc - Legal & Compliance', RecordTypeId=corpRt, Plan_Tier__c='T2', Deal_Model__c='Buying_Centre',
    Plan_Status__c='Active', SoW_Denominator__c=214, Family_Coverage_Pct__c=42, Seat_Penetration_Pct__c=26,
    Review_Cadence__c='Half_Yearly', Next_Review_Date__c=Date.newInstance(2026,9,30),
    Strengths__c='Established Lexology PRO across UK group legal',
    Weaknesses__c='No Intelligence; low counsel penetration (26%)',
    Opportunities__c='214 counsel base; regulation-heavy telco demand',
    Threats__c='Budget consolidation under the new GC');
insert new List<Account_Plan__c>{ law, corp };

// 5) Cells  (spec = 'Family|State|ARR|ExpectedRevenue')
List<Whitespace_Cell__c> cells = new List<Whitespace_Cell__c>();

Map<String, List<String>> lawNodes = new Map<String, List<String>>{
    'London' => new List<String>{
        'Lexology PRO|Owned_Healthy|186000|0', 'Specialist Platforms|In_Renewal|94000|0',
        'Lexology Intelligence|White_Space|0|140000', 'ALM Subs / IS|Owned_Healthy|72000|0',
        'Events & Sponsorship|Booked|28000|0', 'Advertising|Win_Back|0|45000' },
    'Frankfurt' => new List<String>{
        'Lexology PRO|Owned_Healthy|88000|0', 'Specialist Platforms|White_Space|0|66000',
        'Lexology Intelligence|Candidate|0|40000', 'ALM Subs / IS|No_Engagement|0|0',
        'Events & Sponsorship|Booked|12000|0', 'Advertising|White_Space|0|22000' },
    'Paris' => new List<String>{
        'Lexology PRO|In_Renewal|61000|0', 'Specialist Platforms|White_Space|0|48000',
        'Lexology Intelligence|No_Engagement|0|0', 'ALM Subs / IS|NA|0|0',
        'Events & Sponsorship|Candidate|0|9000', 'Advertising|White_Space|0|15000' }
};
for (String node : lawNodes.keySet()) {
    for (String spec : lawNodes.get(node)) {
        List<String> p = spec.split('\\|');
        cells.add(new Whitespace_Cell__c(
            Account_Plan__c=law.Id, Product_Family__c=famId.get(p[0]),
            Node_Type__c='Office_Subsidiary', Node_Key__c=node.toLowerCase(), Node_Label__c=node, Region__c='EMEA',
            State__c=p[1], ARR__c=Decimal.valueOf(p[2]), Expected_Revenue__c=Decimal.valueOf(p[3]),
            Next_Action__c='Auto-seeded', External_Key__c=law.Id+'|'+famId.get(p[0])+'|'+node.toLowerCase()));
    }
}

Map<String, List<String>> corpNodes = new Map<String, List<String>>{
    'Commercial & Disputes' => new List<String>{
        'Lexology PRO|Owned_Healthy|140000|0', 'Specialist Platforms|In_Renewal|62000|0',
        'Lexology Intelligence|White_Space|0|110000', 'ALM Subs / IS|Candidate|0|55000',
        'Events & Sponsorship|Booked|8000|0' },
    'Regulatory & Competition' => new List<String>{
        'Lexology PRO|Owned_Healthy|96000|0', 'Specialist Platforms|White_Space|0|70000',
        'Lexology Intelligence|White_Space|0|120000', 'ALM Subs / IS|No_Engagement|0|0',
        'Events & Sponsorship|Candidate|0|11000' },
    'IP & Privacy' => new List<String>{
        'Lexology PRO|In_Renewal|48000|0', 'Specialist Platforms|Candidate|0|35000',
        'Lexology Intelligence|White_Space|0|90000', 'ALM Subs / IS|No_Engagement|0|0',
        'Events & Sponsorship|White_Space|0|6000' }
};
for (String node : corpNodes.keySet()) {
    for (String spec : corpNodes.get(node)) {
        List<String> p = spec.split('\\|');
        cells.add(new Whitespace_Cell__c(
            Account_Plan__c=corp.Id, Product_Family__c=famId.get(p[0]),
            Node_Type__c='Practice_Function', Node_Key__c=node.toLowerCase().left(60), Node_Label__c=node, Region__c='UK',
            State__c=p[1], ARR__c=Decimal.valueOf(p[2]), Expected_Revenue__c=Decimal.valueOf(p[3]),
            Next_Action__c='Auto-seeded', External_Key__c=corp.Id+'|'+famId.get(p[0])+'|'+node.toLowerCase().left(40)));
    }
}

insert cells;
System.debug('Seeded ' + cells.size() + ' cells across 2 plans (' + law.Id + ', ' + corp.Id + ').');
