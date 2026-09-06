// Create the Free Newsfeed Subscribers campaign + a "Registered" member status (KJDEV).
Campaign existing;
for (Campaign c : [SELECT Id FROM Campaign WHERE Name='Lexology - Free Newsfeed Subscribers' LIMIT 1]) existing = c;
Campaign camp;
if (existing == null) {
    camp = new Campaign(Name='Lexology - Free Newsfeed Subscribers', Type='Other', IsActive=true, Status='In Progress');
    insert camp;
} else {
    camp = existing;
}
System.debug('NFCAMP CAMPAIGN_ID=' + camp.Id);

// Ensure a "Registered" member status exists on the campaign
Boolean hasReg = false;
for (CampaignMemberStatus s : [SELECT Id, Label FROM CampaignMemberStatus WHERE CampaignId=:camp.Id]) {
    System.debug('NFCAMP existing status: ' + s.Label);
    if (s.Label == 'Registered') hasReg = true;
}
if (!hasReg) {
    insert new CampaignMemberStatus(CampaignId=camp.Id, Label='Registered', SortOrder=3, HasResponded=true);
    System.debug('NFCAMP added status: Registered');
}
