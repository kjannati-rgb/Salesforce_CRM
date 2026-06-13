public with sharing class OfficeActivityTimelineController {
    // Rolls up Tasks and Events for a Firm account and every Office account beneath it,
    // INCLUDING activities logged against the contacts and opportunities under those offices.
    // One call; the LWC does all grouping, filtering, and selection client-side. Not cacheable:
    // the component loads imperatively on mount and the Refresh button must return fresh activity,
    // not a client-cached copy.
    //
    // monthsBack : how far back to include PAST activity (default 36). Open/overdue and
    //              upcoming activities are always returned regardless of this window.
    // maxRecords : safety cap applied to Tasks and to Events (each), default 1000.
    @AuraEnabled(cacheable=false)
    public static List<ActivityWrapper> getOfficeActivities(Id accountId, Integer monthsBack, Integer maxRecords) {
        List<ActivityWrapper> results = new List<ActivityWrapper>();
        if (accountId == null) {
            return results;
        }

        Integer windowMonths = (monthsBack != null && monthsBack > 0) ? monthsBack : 36;
        Integer rowCap = (maxRecords != null && maxRecords > 0) ? maxRecords : 1000;
        Date sinceDate = Date.today().addMonths(-windowMonths);

        // 1. Firm itself plus its offices, linked EITHER WAY:
        //    standard Parent Account hierarchy (ParentId) OR custom Firm lookup (Ultimate_Account__c).
        Map<Id, String> accountNameById = new Map<Id, String>();
        for (Account a : [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accountId OR ParentId = :accountId OR Ultimate_Account__c = :accountId
            WITH USER_MODE
        ]) {
            accountNameById.put(a.Id, a.Name);
        }
        Set<Id> accountIds = accountNameById.keySet();

        // 2. Contacts under those offices -> remember which office each belongs to.
        Map<Id, Id> contactToAccount = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            WITH USER_MODE
        ]) {
            contactToAccount.put(c.Id, c.AccountId);
        }

        // 3. Opportunities under those offices -> remember which office each belongs to.
        Map<Id, Id> oppToAccount = new Map<Id, Id>();
        for (Opportunity o : [
            SELECT Id, AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
            WITH USER_MODE
        ]) {
            oppToAccount.put(o.Id, o.AccountId);
        }

        // Activity is "in scope" if WhatId points at an office/opportunity, or WhoId at a contact.
        Set<Id> whatScope = new Set<Id>(accountIds);
        whatScope.addAll(oppToAccount.keySet());
        Set<Id> whoScope = contactToAccount.keySet();

        if (whatScope.isEmpty() && whoScope.isEmpty()) {
            return results;
        }

        // Closed Task statuses, so the LWC can split open/overdue/upcoming from history.
        Set<String> closedStatuses = new Set<String>{ 'Completed' };
        for (TaskStatus ts : [SELECT MasterLabel FROM TaskStatus WHERE IsClosed = true]) {
            closedStatuses.add(ts.MasterLabel);
        }

        Set<Id> ownerIds = new Set<Id>();

        // 4. Tasks in scope, within the window OR still open (so overdue/upcoming never get truncated).
        for (Task t : [
            SELECT Id, Subject, TaskSubtype, Type, ActivityDate, Status, Priority,
                   Description, LastModifiedDate,
                   OwnerId, Owner.Name,
                   WhatId, What.Name,
                   WhoId, Who.Name
            FROM Task
            WHERE (WhatId IN :whatScope OR WhoId IN :whoScope)
              AND (ActivityDate >= :sinceDate OR ActivityDate = null OR Status NOT IN :closedStatuses)
            WITH USER_MODE
            ORDER BY ActivityDate DESC NULLS LAST
            LIMIT :rowCap
        ]) {
            ActivityWrapper w = new ActivityWrapper();
            w.id = t.Id;
            w.objectApiName = 'Task';
            w.subject = t.Subject;
            w.type = mapTaskType(t.TaskSubtype, t.Type);
            w.iconName = iconForType(w.type);
            w.status = t.Status;
            w.statusLabel = 'Status';
            w.priority = t.Priority;
            w.isOpen = !closedStatuses.contains(t.Status);
            w.description = t.Description;
            w.ownerId = t.OwnerId;
            w.ownerName = (t.Owner != null) ? t.Owner.Name : null;
            w.whoId = t.WhoId;
            w.whoName = (t.Who != null) ? t.Who.Name : null;
            w.activityDateTime = (t.ActivityDate != null)
                ? Datetime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0))
                : t.LastModifiedDate;
            resolveOffice(w, t.WhatId, t.WhoId, accountNameById, oppToAccount, contactToAccount);
            stampRelated(w, t.WhatId, (t.What != null ? t.What.Name : null), oppToAccount);
            ownerIds.add(t.OwnerId);
            results.add(w);
        }

        // 5. Events in scope, within the window (future events fall in naturally for "Upcoming").
        for (Event e : [
            SELECT Id, Subject, EventSubtype, ActivityDate, StartDateTime, EndDateTime,
                   Location, Meeting_Status__c, Description, LastModifiedDate,
                   OwnerId, Owner.Name,
                   WhatId, What.Name,
                   WhoId, Who.Name
            FROM Event
            WHERE (WhatId IN :whatScope OR WhoId IN :whoScope)
              AND (ActivityDate >= :sinceDate OR ActivityDate = null)
            WITH USER_MODE
            ORDER BY StartDateTime DESC NULLS LAST
            LIMIT :rowCap
        ]) {
            ActivityWrapper w = new ActivityWrapper();
            w.id = e.Id;
            w.objectApiName = 'Event';
            w.subject = e.Subject;
            w.type = 'Event';
            w.iconName = iconForType('Event');
            // Events have no Task.Status; surface the org's Meeting Status picklist instead.
            w.status = e.Meeting_Status__c;
            w.statusLabel = 'Meeting Status';
            w.priority = null;
            w.isOpen = false;
            w.description = e.Description;
            w.location = e.Location;
            w.ownerId = e.OwnerId;
            w.ownerName = (e.Owner != null) ? e.Owner.Name : null;
            w.whoId = e.WhoId;
            w.whoName = (e.Who != null) ? e.Who.Name : null;
            if (e.StartDateTime != null) {
                w.activityDateTime = e.StartDateTime;
            } else if (e.ActivityDate != null) {
                w.activityDateTime = Datetime.newInstance(e.ActivityDate, Time.newInstance(0, 0, 0, 0));
            } else {
                w.activityDateTime = e.LastModifiedDate;
            }
            resolveOffice(w, e.WhatId, e.WhoId, accountNameById, oppToAccount, contactToAccount);
            stampRelated(w, e.WhatId, (e.What != null ? e.What.Name : null), oppToAccount);
            ownerIds.add(e.OwnerId);
            results.add(w);
        }

        // 6. Owner is polymorphic, so resolve the owning User's Team / LBR Legal Entity separately.
        if (!ownerIds.isEmpty()) {
            Map<Id, User> ownersById = new Map<Id, User>([
                SELECT Id, Team__c, LBR_Legal_Entity__c
                FROM User
                WHERE Id IN :ownerIds
                WITH USER_MODE
            ]);
            for (ActivityWrapper w : results) {
                User u = (w.ownerId != null) ? ownersById.get((Id) w.ownerId) : null;
                if (u != null) {
                    w.ownerTeam = u.Team__c;
                    w.ownerLegalEntity = u.LBR_Legal_Entity__c;
                }
            }
        }

        results.sort();
        return results;
    }

    // Office attribution: prefer the WhatId account/opportunity, else fall back to the WhoId contact.
    private static void resolveOffice(
        ActivityWrapper w, Id whatId, Id whoId,
        Map<Id, String> accountNameById, Map<Id, Id> oppToAccount, Map<Id, Id> contactToAccount
    ) {
        Id officeId;
        if (whatId != null && accountNameById.containsKey(whatId)) {
            officeId = whatId;
        } else if (whatId != null && oppToAccount.containsKey(whatId)) {
            officeId = oppToAccount.get(whatId);
        } else if (whoId != null && contactToAccount.containsKey(whoId)) {
            officeId = contactToAccount.get(whoId);
        }
        if (officeId != null) {
            w.officeId = officeId;
            w.officeName = accountNameById.get(officeId);
        }
    }

    // When the activity is tied to an Opportunity, surface its name for context in the detail pane.
    private static void stampRelated(ActivityWrapper w, Id whatId, String whatName, Map<Id, Id> oppToAccount) {
        if (whatId != null && oppToAccount.containsKey(whatId)) {
            w.relatedToId = whatId;
            w.relatedToName = whatName;
        }
    }

    // Activity categorisation. This org logs calls and emails on the editable Type picklist
    // (e.g. Type = 'Call'), NOT via the Log-a-Call/Email TaskSubtype — though email also arrives
    // through the Groove integration as TaskSubtype 'Email'/'ListEmail'. Honour both signals; every
    // other Type (Demo, Gong Conversation, Customer Journey, etc.) shows as a generic Task.
    // Apex String == is case-insensitive and null-safe, so blank subtype/type fall through cleanly.
    private static String mapTaskType(String subtype, String type) {
        if (subtype == 'Email' || subtype == 'ListEmail') {
            return 'Email';
        }
        if (type == 'Call' || subtype == 'Call') {
            return 'Call';
        }
        if (type == 'Email') {
            return 'Email';
        }
        return 'Task';
    }

    private static String iconForType(String type) {
        switch on type {
            when 'Email' {
                return 'standard:email';
            }
            when 'Call' {
                return 'standard:log_a_call';
            }
            when 'Event' {
                return 'standard:event';
            }
            when else {
                return 'standard:task';
            }
        }
    }

    public class ActivityWrapper implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String subject;
        @AuraEnabled public String type;
        @AuraEnabled public String iconName;
        @AuraEnabled public Datetime activityDateTime;
        @AuraEnabled public Boolean isOpen;
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String priority;
        @AuraEnabled public String ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerTeam;
        @AuraEnabled public String ownerLegalEntity;
        @AuraEnabled public String officeId;
        @AuraEnabled public String officeName;
        @AuraEnabled public String whoId;
        @AuraEnabled public String whoName;
        @AuraEnabled public String relatedToId;
        @AuraEnabled public String relatedToName;
        @AuraEnabled public String description;
        @AuraEnabled public String location;

        // Descending by date; null dates sort last.
        public Integer compareTo(Object other) {
            ActivityWrapper o = (ActivityWrapper) other;
            if (this.activityDateTime == o.activityDateTime) {
                return 0;
            }
            if (this.activityDateTime == null) {
                return 1;
            }
            if (o.activityDateTime == null) {
                return -1;
            }
            return this.activityDateTime > o.activityDateTime ? -1 : 1;
        }
    }
}
