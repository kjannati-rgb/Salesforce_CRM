public with sharing class OpportunityHandler {
    
   
    public static void LockOppRecords(List<Opportunity> NewOppRecords,map<id,Opportunity> OldOppRecords)
    {       
        List<opportunity> LockOppRecords = new List<opportunity>();
        List<opportunity> UnlockOppRecords = new List<opportunity>();
        List<opportunity> SubmitForApproval = new List<opportunity>();
        boolean flag = checkFlag.flag;
        for(opportunity opp : NewOppRecords)
        {
            
            if(opp.StageName=='Closed Won – Pending Approval' || opp.StageName=='Closed Won'|| opp.StageName=='Closed Lost' || opp.StageName=='Cancellation - Pending Review' ||opp.StageName=='Closed Won - Cancellation')
            {
                if(!Approval.isLocked(opp.id) && flag)
                    LockOppRecords.add(opp);
             
                if(OldOppRecords!=null && OldOppRecords.get(opp.id).StageName!=opp.StageName && (opp.StageName=='Closed Won – Pending Approval' || opp.StageName=='Cancellation - Pending Review'))
                { 
                    SubmitForApproval.add(opp);
                }else if(OldOppRecords==null &&  (opp.StageName=='Closed Won – Pending Approval' || opp.StageName=='Cancellation - Pending Review'))
                {
                    SubmitForApproval.add(opp);
                }
            }
            else{
                if(Approval.isLocked(opp.id) && flag)
                {
                    UnlockOppRecords.add(opp);
                }
               

            }
        }
        system.debug('all lock record list:'+LockOppRecords);
         system.debug('all unlock record list:'+UnlockOppRecords);
         system.debug('all submit for approval record list:'+SubmitForApproval);
        
        /*  for(Approval.LockResult lr : allLockRecords) {
if (lr.isSuccess()) {
System.debug('Successfully locked Opportunity with ID: ' + lr.getId());
}
else {
// Operation failed, so get all errors                
for(Database.Error err : lr.getErrors()) {
System.debug('The following error has occurred.');                    
System.debug(err.getStatusCode() + ': ' + err.getMessage());
System.debug('Quote fields that affected this error: ' + err.getFields());
}
}
}*/
        
        // system.debug('flag: '+CheckFlag.flag);
        
        
        
        for(opportunity OppForApproval : SubmitForApproval)
        {
            //system.debug('a: '+a);
            
            system.debug('Approval Submission');
           // system.debug(OldOppRecords.get(OppForApproval.id).StageName!=OppForApproval.StageName);
           // system.debug(OldOppRecords!=null);
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
