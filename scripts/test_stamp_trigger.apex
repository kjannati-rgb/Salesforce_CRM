Id opp='006Ae00000obPM1IAM';
// clean slate
update new Opportunity(Id=opp, Client_Engagement_Director__c=null, Sales_Development_Representative__c=null);
delete [SELECT Id FROM OpportunityTeamMember WHERE OpportunityId=:opp AND TeamMemberRole IN ('Client Engagement Director','Sales Development Representative')];
Opportunity before=[SELECT Client_Engagement_Director__c, Sales_Development_Representative__c FROM Opportunity WHERE Id=:opp];
System.debug('BEFORE CED='+before.Client_Engagement_Director__c+' SDR='+before.Sales_Development_Representative__c);

// simulate NON-flow adds (data-load style direct insert)
insert new List<OpportunityTeamMember>{
  new OpportunityTeamMember(OpportunityId=opp, UserId='005Px00000Bje4fIAB', TeamMemberRole='Client Engagement Director', OpportunityAccessLevel='Edit'),
  new OpportunityTeamMember(OpportunityId=opp, UserId='005Px00000Bje4gIAB', TeamMemberRole='Sales Development Representative', OpportunityAccessLevel='Edit')
};

Opportunity after=[SELECT Client_Engagement_Director__c, Sales_Development_Representative__c FROM Opportunity WHERE Id=:opp];
System.debug('AFTER  CED='+after.Client_Engagement_Director__c+' SDR='+after.Sales_Development_Representative__c);
System.debug('EXPECT CED=005Px00000Bje4fIAB SDR=005Px00000Bje4gIAB');
System.debug(after.Client_Engagement_Director__c=='005Px00000Bje4fIAB' && after.Sales_Development_Representative__c=='005Px00000Bje4gIAB' ? 'TEST_PASS' : 'TEST_FAIL');
