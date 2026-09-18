// PROD smoke test - everything is rolled back by the exception at the end (no emails/async fire on rollback).
Id openOpp = '006Px00000VPrdaIAD', prev = '006Px00000VPmIzIAL';            // open Identify opp / recent Closed Won opp, both with no team
Id se = '005Px000009fBFLIA2', ced = '005Px00000A9kvVIAR', sdr = '005Px000009RoOXIA0'; // Jessica Silveira / Joseph Green / Kit Potter
// T1: record-triggered stamp - SE added directly (data-load style) stamps the field
insert new OpportunityTeamMember(OpportunityId = openOpp, UserId = se, TeamMemberRole = 'Solutions Engineer', OpportunityAccessLevel = 'Read');
System.debug('SMOKE T1 SE stamped on open opp: ' + ([SELECT Solutions_Engineer__c FROM Opportunity WHERE Id = :openOpp].Solutions_Engineer__c == se ? 'PASS' : 'FAIL'));
// T2: real renewal path - new opp with Previous_Opportunity__c fires the master Opportunity flow -> sync V4
insert new List<OpportunityTeamMember>{
  new OpportunityTeamMember(OpportunityId = prev, UserId = se,  TeamMemberRole = 'Solutions Engineer', OpportunityAccessLevel = 'Read'),
  new OpportunityTeamMember(OpportunityId = prev, UserId = ced, TeamMemberRole = 'Client Engagement Director', OpportunityAccessLevel = 'Read'),
  new OpportunityTeamMember(OpportunityId = prev, UserId = sdr, TeamMemberRole = 'Sales Development Representative', OpportunityAccessLevel = 'Read')};
Opportunity p = [SELECT AccountId, RecordTypeId, CurrencyIsoCode, OwnerId, Solutions_Engineer__c FROM Opportunity WHERE Id = :prev];
System.debug('SMOKE info prev (closed won) SE stamped: ' + (p.Solutions_Engineer__c == se));
Opportunity ren = new Opportunity(Name = 'ZZ SE smoke test renewal', AccountId = p.AccountId, RecordTypeId = p.RecordTypeId, CurrencyIsoCode = p.CurrencyIsoCode,
    OwnerId = p.OwnerId, StageName = 'Identify', CloseDate = Date.today().addYears(1), Type = 'Repeat Business', LeadSource = 'Renewal', Previous_Opportunity__c = prev);
insert ren;
Map<String, Id> roles = new Map<String, Id>();
for (OpportunityTeamMember t : [SELECT TeamMemberRole, UserId FROM OpportunityTeamMember WHERE OpportunityId = :ren.Id]) roles.put(t.TeamMemberRole, t.UserId);
Opportunity r = [SELECT Solutions_Engineer__c, Client_Engagement_Director__c, Sales_Development_Representative__c FROM Opportunity WHERE Id = :ren.Id];
System.debug('SMOKE T2 renewal team copied by the real master flow: ' + roles.keySet());
System.debug('SMOKE T2 SE NOT carried to renewal: ' + (!roles.containsKey('Solutions Engineer') && r.Solutions_Engineer__c == null ? 'PASS' : 'FAIL'));
System.debug('SMOKE T2 CED carried + stamped: ' + (roles.get('Client Engagement Director') == ced && r.Client_Engagement_Director__c == ced ? 'PASS' : 'FAIL ' + r.Client_Engagement_Director__c));
System.debug('SMOKE T2 SDR carried + stamped: ' + (roles.get('Sales Development Representative') == sdr && r.Sales_Development_Representative__c == sdr ? 'PASS' : 'FAIL ' + r.Sales_Development_Representative__c));
System.debug('SMOKE limits SOQL ' + Limits.getQueries() + '/' + Limits.getLimitQueries() + ' DML ' + Limits.getDmlStatements());
throw new HandledException('ROLLBACK - prod smoke test complete, all data discarded');
