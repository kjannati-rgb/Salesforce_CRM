public with sharing class OpportunityChangePublisher {
    /**
* Publishes Opportunity_Change__e events for Opportunities whose related Account
* has a non-blank MBL_Seminars_FirmID__c.
*
* @param newList   Trigger.new
* @param oldMap    Trigger.oldMap (null on insert)
* @return Integer  Number of successfully published events for Testing
*/
    public static Integer publishFor(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (newList == null || newList.isEmpty()) return 0;
		//if (System.Label.MBL_Custom_Event != 'True') return 0;

        Ast_Trigger_Setting__mdt setting = [SELECT IsActive__c FROM Ast_Trigger_Setting__mdt WHERE DeveloperName = 'MBL_Custom_Event' LIMIT 1];
        if (setting != null && !setting.IsActive__c) return 0;
        
        // Gather AccountIds to check the FirmID on the Account
        Set<Id> accountIds = new Set<Id>();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : newList) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
            oppIds.add(o.Id);
        }
        system.debug(oppIds);
        
        if (accountIds.isEmpty()) return 0; 
        
        // Query Accounts for the Firm ID field
        Map<Id, Account> acctById = new Map<Id, Account>(
            [SELECT Id, MBL_Seminars_FirmID__c
             FROM Account
             WHERE Id IN :accountIds]
        );
        
        Integer Accountcount=0;
        
        for(Account ITcheckmblid:acctById.values()){
            if(ITcheckmblid.MBL_Seminars_FirmID__c!=null){
                Accountcount++;
            }
        }
       
        if(Accountcount==0) return 0;

        
        
        // Query Opportunities with Owner and Expected Revenue fields
        Map<Id, Opportunity> oppById = new Map<Id, Opportunity>(
            [SELECT Id, OwnerId, Amount, StageName, LastModifiedDate,
             Owner.Email, Owner.FirstName, Owner.LastName,
             AccountId, Opportunity_Salesforce_ID__c
             FROM Opportunity
             WHERE Id IN :oppIds]
        );
        system.debug(oppById);
        
        // Build events
        List<Opportunity_Change__e> events = new List<Opportunity_Change__e>();
        
        for (Opportunity o : newList) {
            Opportunity fullOpp = oppById.get(o.Id);
            system.debug(fullOpp);
            if (fullOpp == null) continue;
            
            Account a = acctById.get(fullOpp.AccountId);
            system.debug(a);
            if (a == null) continue;
            
            String firmId = a.MBL_Seminars_FirmID__c;
            system.debug(firmId);
            if (String.isBlank(firmId)) continue; // Only publish if Account has FirmID
            
            // If org stores the SFDC Id in a custom field, use it.
            // Otherwise, we'll fall back to the actual o.Id.
            String oppExternal = null;
            try {
                // This works if the field exists or catch and fallback
                oppExternal = (String)fullOpp.get('Opportunity_Salesforce_ID__c');
            } catch (Exception ignore) {}
            
            if (String.isBlank(oppExternal)) {
                oppExternal = fullOpp.Id; // fallback to real Id
            }
            
            Datetime lastModified = fullOpp.LastModifiedDate;
            system.debug(lastModified);
            
            events.add(new Opportunity_Change__e(
                IsInsert__c                       = isInsert,
                IsUpdate__c                       = isUpdate,
                MBL_Seminars_FirmID__c            = firmId,
                Opportunity_Salesforce_ID__c      = oppExternal,
                StageName__c                      = fullOpp.StageName,
                LastModified__c                   = lastModified,
                ExpectedRevenue__c                = fullOpp.Amount,
                OwnerId__c                        = fullOpp.OwnerId,
                OwnerEmail__c                     = fullOpp.Owner.Email,
                OwnerFirstName__c                 = fullOpp.Owner.FirstName,
                OwnerLastName__c                  = fullOpp.Owner.LastName
            ));
        }
        system.debug(events);
        if (events.isEmpty()) return 0;
        
        // Publish in bulk
        List<Database.SaveResult> results = EventBus.publish(events);
        system.debug(results);
        Integer successCount = 0;
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) successCount++;
            system.debug(successCount);
            //TODO: add logging for errors
        }
        
        return successCount;
    }
}
