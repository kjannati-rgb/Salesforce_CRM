public with sharing class OpportunityHandler {

    private static final Set<String> CLOSED_STAGES = new Set<String>{
        'Closed Won – Pending Approval',
        'Closed Won',
        'Closed Lost',
        'Cancellation - Pending Review',
        'Closed Won - Cancellation'
    };

    // Ids whose lock state has already been handled this transaction. CPQ and the flow
    // chain re-save the same Opportunity several times per commit; without this, every
    // save repeats the lock work (a workflow field update also replays the trigger with
    // the original old values, re-detecting the same stage transition).
    @TestVisible
    private static Set<Id> processedLockIds = new Set<Id>();

    public static void LockOppRecords(List<Opportunity> NewOppRecords,map<id,Opportunity> OldOppRecords)
    {
        List<opportunity> lockCandidates = new List<opportunity>();
        List<opportunity> unlockCandidates = new List<opportunity>();
        List<opportunity> LockOppRecords = new List<opportunity>();
        List<opportunity> UnlockOppRecords = new List<opportunity>();
        List<opportunity> SubmitForApproval = new List<opportunity>();
        boolean flag = checkFlag.flag;
        for(opportunity opp : NewOppRecords)
        {
            Boolean closedNow = CLOSED_STAGES.contains(opp.StageName);

            if(closedNow)
            {
                if(OldOppRecords!=null && OldOppRecords.get(opp.id).StageName!=opp.StageName && (opp.StageName=='Closed Won – Pending Approval' || opp.StageName=='Cancellation - Pending Review'))
                {
                    SubmitForApproval.add(opp);
                }else if(OldOppRecords==null &&  (opp.StageName=='Closed Won – Pending Approval' || opp.StageName=='Cancellation - Pending Review'))
                {
                    SubmitForApproval.add(opp);
                }
            }

            if(!flag || processedLockIds.contains(opp.id)) continue;

            if(OldOppRecords==null)
            {
                // Insert: a brand-new record can never be Approval-locked, so records
                // created directly in a closed stage lock without an isLocked() check.
                if(closedNow)
                {
                    LockOppRecords.add(opp);
                    processedLockIds.add(opp.id);
                }
                continue;
            }

            // Only a save whose stage actually crosses the closed/open boundary can
            // change the required lock state — anything else skips the lock API.
            Boolean closedBefore = CLOSED_STAGES.contains(OldOppRecords.get(opp.id).StageName);
            if(closedNow == closedBefore) continue;

            if(closedNow)
            {
                lockCandidates.add(opp);
            }
            else
            {
                unlockCandidates.add(opp);
            }
            processedLockIds.add(opp.id);
        }

        // One bulk isLocked() call per invocation instead of one per record.
        if(!lockCandidates.isEmpty() || !unlockCandidates.isEmpty())
        {
            List<Id> idsToCheck = new List<Id>();
            for(opportunity opp : lockCandidates) idsToCheck.add(opp.id);
            for(opportunity opp : unlockCandidates) idsToCheck.add(opp.id);
            Map<Id,Boolean> lockedById = Approval.isLocked(idsToCheck);
            for(opportunity opp : lockCandidates)
            {
                if(lockedById.get(opp.id) != true) LockOppRecords.add(opp);
            }
            for(opportunity opp : unlockCandidates)
            {
                if(lockedById.get(opp.id) == true) UnlockOppRecords.add(opp);
            }
        }

        system.debug('all lock record list:'+LockOppRecords);
         system.debug('all unlock record list:'+UnlockOppRecords);
         system.debug('all submit for approval record list:'+SubmitForApproval);

        for(opportunity OppForApproval : SubmitForApproval)
        {
            system.debug('Approval Submission');
            if(OldOppRecords!=null && OldOppRecords.get(OppForApproval.id).StageName!=OppForApproval.StageName)
            {
              List<sbaa__Approval__c> abc =   SBAA.ApprovalAPI.submit(OppForApproval.Id,sbaa__Approval__c.sbaa__Opportunity__c);
                system.debug(abc);
                system.debug('Approved update');
            }
            else if(OldOppRecords==null){
                SBAA.ApprovalAPI.submit(OppForApproval.Id,sbaa__Approval__c.sbaa__Opportunity__c);
                 system.debug('Approved insert');
            }
        }

        if(!LockOppRecords.isEmpty()){
            List<Approval.LockResult> allLockRecords = Approval.lock(LockOppRecords,false);
            system.debug('lockrecords-'+allLockRecords);
        }

        if(!UnlockOppRecords.isEmpty())
        {
        List<Approval.UnlockResult> allUnlockRecords = Approval.Unlock(UnlockOppRecords,false);
            system.debug('Unlockrecords-'+allUnlockRecords);
           }
    }
}
