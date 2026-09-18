// Direct test of Opportunity_Sync_Opportunity_Team (the renewal team copier), invoked exactly as the master
// Opportunity flow invokes it (recordId = new opp, isnew_check = true). Proves: every role copies EXCEPT
// Solutions Engineer, and the SE field stays blank on the renewal. Rolls everything back at the end.
Id prev = '006Ae00000ppSL3IAM'; // KJDEV Closed Won opp (Previous_Opportunity__c only accepts Closed Won)
Id se = '005Px00000Bje4fIAB', ced = '005Px00000Bje4gIAB', sdr = '005Px00000Bje4hIAB';
delete [SELECT Id FROM OpportunityTeamMember WHERE OpportunityId = :prev];
insert new List<OpportunityTeamMember>{
  new OpportunityTeamMember(OpportunityId = prev, UserId = se,  TeamMemberRole = 'Solutions Engineer', OpportunityAccessLevel = 'Edit'),
  new OpportunityTeamMember(OpportunityId = prev, UserId = ced, TeamMemberRole = 'Client Engagement Director', OpportunityAccessLevel = 'Edit'),
  new OpportunityTeamMember(OpportunityId = prev, UserId = sdr, TeamMemberRole = 'Sales Development Representative', OpportunityAccessLevel = 'Edit')};
Set<String> prevRoles = new Set<String>(); for (OpportunityTeamMember t : [SELECT TeamMemberRole FROM OpportunityTeamMember WHERE OpportunityId = :prev]) prevRoles.add(t.TeamMemberRole);
System.debug('RESULT prev team roles (source): ' + prevRoles);
FlowDefinitionView fdv = [SELECT ActiveVersionId FROM FlowDefinitionView WHERE ApiName = 'Opportunity_Sync_Opportunity_Team'];
System.debug('RESULT sync flow active version id at run time: ' + fdv.ActiveVersionId);
Opportunity p = [SELECT AccountId, RecordTypeId, CurrencyIsoCode, OwnerId FROM Opportunity WHERE Id = :prev];
Opportunity ren = new Opportunity(Name = 'SE renewal test', AccountId = p.AccountId, RecordTypeId = p.RecordTypeId, CurrencyIsoCode = p.CurrencyIsoCode,
    OwnerId = p.OwnerId, StageName = 'Identify', CloseDate = Date.today().addYears(1), Type = 'Repeat Business', LeadSource = 'Renewal', Previous_Opportunity__c = prev);
insert ren;
// pass the record the way the master flow's $Record does: the sync flow reads Opportunity_Salesforce_ID__c (new OTM's
// OpportunityId) and Previous_Opportunity__r.Client_Engagement_Director__c (CED carried to the renewal)
Opportunity recIn = [SELECT Id, Opportunity_Salesforce_ID__c, Previous_Opportunity__c, Previous_Opportunity__r.Client_Engagement_Director__c, AccountId, OwnerId FROM Opportunity WHERE Id = :ren.Id];
Flow.Interview fi = Flow.Interview.createInterview('Opportunity_Sync_Opportunity_Team',
    new Map<String, Object>{ 'recordId' => recIn, 'isnew_check' => true, 'fault_recipients' => new List<String>() });
fi.start();
Map<String, Id> roles = new Map<String, Id>();
for (OpportunityTeamMember t : [SELECT TeamMemberRole, UserId FROM OpportunityTeamMember WHERE OpportunityId = :ren.Id]) roles.put(t.TeamMemberRole, t.UserId);
Opportunity r = [SELECT Solutions_Engineer__c, Client_Engagement_Director__c, Sales_Development_Representative__c FROM Opportunity WHERE Id = :ren.Id];
System.debug('RESULT renewal team roles copied: ' + roles.keySet());
System.debug('RESULT SE NOT copied to renewal team: ' + (!roles.containsKey('Solutions Engineer') ? 'PASS' : 'FAIL'));
System.debug('RESULT SE field blank on renewal: ' + (r.Solutions_Engineer__c == null ? 'PASS' : 'FAIL ' + r.Solutions_Engineer__c));
System.debug('RESULT CED copied + stamped: ' + (roles.get('Client Engagement Director') == ced && r.Client_Engagement_Director__c == ced ? 'PASS' : 'FAIL ' + roles.get('Client Engagement Director') + ' / ' + r.Client_Engagement_Director__c));
System.debug('RESULT SDR copied + stamped: ' + (roles.get('Sales Development Representative') == sdr && r.Sales_Development_Representative__c == sdr ? 'PASS' : 'FAIL ' + roles.get('Sales Development Representative') + ' / ' + r.Sales_Development_Representative__c));
throw new HandledException('ROLLBACK - test complete, discarding all test data');
