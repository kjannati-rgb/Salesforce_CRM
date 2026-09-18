Id opp = '006Ae00000obPM1IAM';
Id se = '005Px00000Bje4fIAB', ced = '005Px00000Bje4gIAB', sdr = '005Px00000Bje4hIAB';
List<String> roles = new List<String>{'Solutions Engineer','Client Engagement Director','Sales Development Representative'};
// clean slate
delete [SELECT Id FROM OpportunityTeamMember WHERE OpportunityId = :opp AND (TeamMemberRole IN :roles OR UserId IN (:se,:ced,:sdr))];
update new Opportunity(Id = opp, Solutions_Engineer__c = null, Client_Engagement_Director__c = null, Sales_Development_Representative__c = null);

// T1: SE added directly (data-load style) -> trigger must stamp
OpportunityTeamMember m = new OpportunityTeamMember(OpportunityId = opp, UserId = se, TeamMemberRole = 'Solutions Engineer', OpportunityAccessLevel = 'Edit');
insert m;
Opportunity o = [SELECT Solutions_Engineer__c FROM Opportunity WHERE Id = :opp];
System.debug('RESULT T1 SE stamped on insert: ' + (o.Solutions_Engineer__c == se ? 'PASS' : 'FAIL got ' + o.Solutions_Engineer__c));

// T2: update of the SE member keeps the stamp
m.OpportunityAccessLevel = 'Read'; update m;
o = [SELECT Solutions_Engineer__c FROM Opportunity WHERE Id = :opp];
System.debug('RESULT T2 SE stamp survives member update: ' + (o.Solutions_Engineer__c == se ? 'PASS' : 'FAIL'));

// T3: regression - CED + SDR still stamp, SE untouched
insert new List<OpportunityTeamMember>{
    new OpportunityTeamMember(OpportunityId = opp, UserId = ced, TeamMemberRole = 'Client Engagement Director', OpportunityAccessLevel = 'Edit'),
    new OpportunityTeamMember(OpportunityId = opp, UserId = sdr, TeamMemberRole = 'Sales Development Representative', OpportunityAccessLevel = 'Edit')};
o = [SELECT Solutions_Engineer__c, Client_Engagement_Director__c, Sales_Development_Representative__c FROM Opportunity WHERE Id = :opp];
System.debug('RESULT T3 regression CED/SDR stamp + SE intact: ' + (o.Client_Engagement_Director__c == ced && o.Sales_Development_Representative__c == sdr && o.Solutions_Engineer__c == se ? 'PASS' : 'FAIL ' + o));

// T4: a non-stamping role must NOT touch the fields
insert new OpportunityTeamMember(OpportunityId = opp, UserId = '0056g000004G0DvAAK', TeamMemberRole = 'CS Contact', OpportunityAccessLevel = 'Read');
