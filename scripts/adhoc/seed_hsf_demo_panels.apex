// Demo/showcase data for the 4 manually-populated Account Plan panels (Key Signals, Objectives,
// Stakeholder Heat-Map, Plan Team) on the REAL Herbert Smith Freehills plan — everything below is
// clearly prefixed "[DEMO]" so it can never be mistaken for real reconnaissance on a real client, and
// is trivially findable/removable later via "WHERE Name LIKE '%[DEMO]%'" (or Summary__c/Stakeholder_Name__c).
// The objective + signals deliberately reference REAL findings from this session (the London Performance
// Data renewal risk, the 4-office Lexology In-Depth win-back cluster) so the demo teaches the intended
// workflow rather than being arbitrary placeholder text.
Id planId = 'a7nAd000000C5lVIAS';

Map<String, Id> famByName = new Map<String, Id>();
for (Plan_Product_Family__c f : [
    SELECT Id, Name FROM Plan_Product_Family__c
    WHERE Name IN ('Lexology PRO', 'Lexology In-Depth', 'Performance Data - GxR/IP')
]) {
    famByName.put(f.Name, f.Id);
}

List<Plan_Stakeholder__c> stakeholders = new List<Plan_Stakeholder__c>{
    new Plan_Stakeholder__c(Account_Plan__c = planId, Stakeholder_Name__c = '[DEMO] Sarah Whitfield',
        Role__c = 'General Counsel', Influence__c = 'High', Sentiment__c = 'Champion',
        Buying_Center__c = 'Group Legal'),
    new Plan_Stakeholder__c(Account_Plan__c = planId, Stakeholder_Name__c = '[DEMO] David Chen',
        Role__c = 'Head of Procurement', Influence__c = 'High', Sentiment__c = 'Neutral',
        Buying_Center__c = 'Procurement'),
    new Plan_Stakeholder__c(Account_Plan__c = planId, Stakeholder_Name__c = '[DEMO] Priya Nair',
        Role__c = 'Knowledge Management Lead', Influence__c = 'Medium', Sentiment__c = 'Supporter',
        Buying_Center__c = 'Knowledge & Innovation'),
    new Plan_Stakeholder__c(Account_Plan__c = planId, Stakeholder_Name__c = '[DEMO] Marcus Webb',
        Role__c = 'IT Director', Influence__c = 'Medium', Sentiment__c = 'Detractor',
        Buying_Center__c = 'IT')
};
insert stakeholders;

List<Plan_Objective__c> objectives = new List<Plan_Objective__c>{
    new Plan_Objective__c(Account_Plan__c = planId, Name = '[DEMO] Secure Performance Data renewal — London',
        Status__c = 'At_Risk', Progress_Pct__c = 20, Target_Amount__c = 157000,
        Due_Date__c = Date.today().addDays(45), Linked_Family__c = famByName.get('Performance Data - GxR/IP')),
    new Plan_Objective__c(Account_Plan__c = planId, Name = '[DEMO] Win back Lexology In-Depth (4 offices)',
        Status__c = 'Not_Started', Progress_Pct__c = 0, Target_Amount__c = 150000,
        Due_Date__c = Date.today().addDays(90), Linked_Family__c = famByName.get('Lexology In-Depth')),
    new Plan_Objective__c(Account_Plan__c = planId, Name = '[DEMO] Expand Lexology PRO seats firm-wide',
        Status__c = 'In_Progress', Progress_Pct__c = 45, Target_Amount__c = 75000,
        Due_Date__c = Date.today().addDays(60), Linked_Family__c = famByName.get('Lexology PRO'))
};
insert objectives;

List<Plan_Signal__c> signals = new List<Plan_Signal__c>{
    new Plan_Signal__c(Account_Plan__c = planId, Signal_Type__c = 'Risk', Severity__c = 'High',
        Source__c = 'Whitespace_Cell', Status__c = 'Open', Detected_Date__c = Date.today(),
        Summary__c = '[DEMO] Performance Data (GxR/IP) renewal at London due within 90 days',
        Recommended_Action__c = 'Schedule renewal conversation before the contract lapses'),
    new Plan_Signal__c(Account_Plan__c = planId, Signal_Type__c = 'Churn', Severity__c = 'High',
        Source__c = 'Whitespace_Cell', Status__c = 'Open', Detected_Date__c = Date.today(),
        Summary__c = '[DEMO] Lexology In-Depth lapsed at 4 offices with no renewal',
        Recommended_Action__c = 'Re-engage Moscow, Beijing, Shanghai and Johannesburg offices'),
    new Plan_Signal__c(Account_Plan__c = planId, Signal_Type__c = 'Expansion', Severity__c = 'Medium',
        Source__c = 'CPQ', Status__c = 'Open', Detected_Date__c = Date.today(),
        Summary__c = '[DEMO] Strong Lexology PRO usage signals a firm-wide cross-sell opportunity',
        Recommended_Action__c = 'Propose firm-wide PRO expansion at next QBR')
};
insert signals;

insert new Plan_Team_Member__c(Account_Plan__c = planId, User__c = UserInfo.getUserId(),
    Plan_Role__c = 'Plan_Lead');

System.debug('DEMO_SEED_DONE stakeholders=' + stakeholders.size()
    + ' objectives=' + objectives.size() + ' signals=' + signals.size());
