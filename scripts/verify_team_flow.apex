Id oppId = '006Ae00000obPM1IAM';

// --- (A) Persistent seed: two CS Contact members for the UI run-through ---
List<OpportunityTeamMember> seed = new List<OpportunityTeamMember>{
    new OpportunityTeamMember(OpportunityId=oppId, UserId='005Px00000Bje4hIAB', TeamMemberRole='CS Contact', OpportunityAccessLevel='Edit'),
    new OpportunityTeamMember(OpportunityId=oppId, UserId='005Px00000Bje4gIAB', TeamMemberRole='CS Contact', OpportunityAccessLevel='Edit')
};
try { insert seed; System.debug('SEED_OK: inserted '+seed.size()+' CS Contact members'); }
catch(Exception e){ System.debug('SEED_FAIL: '+e.getMessage()); }

// --- (B) Probes (rolled back) ---
Savepoint sp = Database.setSavepoint();

// Probe 1: OTM duplicate key (Ken is already on team as SDR)
try {
    insert new OpportunityTeamMember(OpportunityId=oppId, UserId='005Tm0000005qh7IAA', TeamMemberRole='CS Contact', OpportunityAccessLevel='Read');
    System.debug('DUP_PROBE: NO error returned (duplicate guard would be the only protection)');
} catch(Exception e){ System.debug('DUP_PROBE: blocked as expected -> '+e.getMessage()); }

// Probe 2: does CS_Contact__c (multi-select picklist) accept person-name values?
try {
    update new Opportunity(Id=oppId, CS_Contact__c='Arnold Bernas;Anna Lorraine Pulumbarit');
    System.debug('MSP_PROBE: name values ACCEPTED (field is unrestricted -> value sprawl)');
} catch(Exception e){ System.debug('MSP_PROBE: name values REJECTED -> '+e.getMessage()); }

Database.rollback(sp);
System.debug('PROBES_ROLLED_BACK');
