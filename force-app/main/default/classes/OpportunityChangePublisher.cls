public with sharing class OpportunityChangePublisher {

    // Per-transaction caches — CPQ and the flow chain re-save the same records several
    // times per commit; account and owner lookups only run for ids not yet seen.
    @TestVisible private static Map<Id, Account> accountCache = new Map<Id, Account>();
    @TestVisible private static Set<Id> accountCacheIds = new Set<Id>();
    @TestVisible private static Map<Id, User> ownerCache = new Map<Id, User>();

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

        // Only the fields the event payload carries are relevant — when none of them
        // changed this save, skip everything (queries included). Inserts always qualify.
        List<Opportunity> relevant = new List<Opportunity>();
        for (Opportunity o : newList) {
            if (o.AccountId == null) continue;
            if (oldMap != null && oldMap.containsKey(o.Id)) {
                Opportunity oldOpp = oldMap.get(o.Id);
                Boolean payloadChanged = oldOpp.StageName != o.StageName
                    || oldOpp.Amount != o.Amount
                    || oldOpp.OwnerId != o.OwnerId
                    || oldOpp.AccountId != o.AccountId;
                if (!payloadChanged) continue;
            }
            relevant.add(o);
        }
        if (relevant.isEmpty()) return 0;

        // CMDT kill switch via the cached registry — no SOQL
        Ast_Trigger_Setting__mdt setting = Ast_Trigger_Setting__mdt.getInstance('MBL_Custom_Event');
        if (setting == null || !setting.IsActive__c) return 0;

        // Account firm ids for accounts not already cached this transaction
        Set<Id> accountsToQuery = new Set<Id>();
        for (Opportunity o : relevant) {
            if (!accountCacheIds.contains(o.AccountId)) accountsToQuery.add(o.AccountId);
        }
        if (!accountsToQuery.isEmpty()) {
            for (Account a : [SELECT Id, MBL_Seminars_FirmID__c FROM Account WHERE Id IN :accountsToQuery]) {
                accountCache.put(a.Id, a);
            }
            accountCacheIds.addAll(accountsToQuery);
        }

        // Owner name/email is the only event data not already on the trigger records —
        // one cached lookup instead of re-querying the Opportunities themselves.
        Set<Id> ownersToQuery = new Set<Id>();
        for (Opportunity o : relevant) {
            Account a = accountCache.get(o.AccountId);
            if (a == null || String.isBlank(a.MBL_Seminars_FirmID__c)) continue;
            if (o.OwnerId != null && !ownerCache.containsKey(o.OwnerId)) ownersToQuery.add(o.OwnerId);
        }
        if (!ownersToQuery.isEmpty()) {
            for (User u : [SELECT Id, Email, FirstName, LastName FROM User WHERE Id IN :ownersToQuery]) {
                ownerCache.put(u.Id, u);
            }
        }

        // Build events straight from the trigger records
        List<Opportunity_Change__e> events = new List<Opportunity_Change__e>();

        for (Opportunity o : relevant) {
            Account a = accountCache.get(o.AccountId);
            if (a == null) continue;

            String firmId = a.MBL_Seminars_FirmID__c;
            if (String.isBlank(firmId)) continue; // Only publish if Account has FirmID

            // If org stores the SFDC Id in a custom field, use it.
            // Otherwise, fall back to the actual o.Id.
            String oppExternal = o.Opportunity_Salesforce_ID__c;
            if (String.isBlank(oppExternal)) {
                oppExternal = o.Id;
            }

            User owner = (o.OwnerId != null) ? ownerCache.get(o.OwnerId) : null;

            events.add(new Opportunity_Change__e(
                IsInsert__c                       = isInsert,
                IsUpdate__c                       = isUpdate,
                MBL_Seminars_FirmID__c            = firmId,
                Opportunity_Salesforce_ID__c      = oppExternal,
                StageName__c                      = o.StageName,
                LastModified__c                   = o.LastModifiedDate,
                ExpectedRevenue__c                = o.Amount,
                OwnerId__c                        = o.OwnerId,
                OwnerEmail__c                     = owner != null ? owner.Email : null,
                OwnerFirstName__c                 = owner != null ? owner.FirstName : null,
                OwnerLastName__c                  = owner != null ? owner.LastName : null
            ));
        }
        if (events.isEmpty()) return 0;

        // Publish in bulk
        List<Database.SaveResult> results = EventBus.publish(events);
        Integer successCount = 0;
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) successCount++;
            //TODO: add logging for errors
        }

        return successCount;
    }
}
