public with sharing class OfficeActivityTimelineController {
    // Rolls up Tasks and Events for a Firm account and every Office account beneath it,
    // INCLUDING activities logged against the contacts and opportunities under those offices.
    // Not cacheable: the component loads imperatively on mount and Refresh must return fresh data.
    //
    // The structured filters (officeId / ownerId / team / legalEntity / searchTerm) are applied
    // SERVER-SIDE in the SOQL, so they reach activity beyond the maxRecords row cap — e.g. filtering
    // a 3,000-task firm by one owner returns all of that owner's activity even if it's old. The LWC's
    // type tabs stay client-side. Pass them all null/blank for the default (unfiltered) load.
    //
    // monthsBack : how far back to include PAST activity (default 36). Open/overdue and upcoming
    //              activities are always returned regardless of this window.
    // maxRecords : safety cap applied to Tasks and to Events (each), default 1000.
    @AuraEnabled(cacheable=false)
    public static TimelineResult getOfficeActivities(
        Id accountId, Integer monthsBack, Integer maxRecords,
        Id officeId, Id ownerId, String team, String legalEntity, String searchTerm
    ) {
        TimelineResult out = new TimelineResult();
        List<ActivityWrapper> results = out.activities;
        if (accountId == null) {
            return out;
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
        for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds WITH USER_MODE]) {
            contactToAccount.put(c.Id, c.AccountId);
        }

        // 3. Opportunities under those offices -> remember which office each belongs to.
        Map<Id, Id> oppToAccount = new Map<Id, Id>();
        for (Opportunity o : [SELECT Id, AccountId FROM Opportunity WHERE AccountId IN :accountIds WITH USER_MODE]) {
            oppToAccount.put(o.Id, o.AccountId);
        }

        // Activity is "in scope" if WhatId points at an office/opportunity, or WhoId at a contact.
        Set<Id> whatScope = new Set<Id>(accountIds);
        whatScope.addAll(oppToAccount.keySet());
        Set<Id> whoScope = contactToAccount.keySet();
        if (whatScope.isEmpty() && whoScope.isEmpty()) {
            return out;
        }

        // Closed Task statuses, so the LWC can split open/overdue/upcoming from history.
        Set<String> closedStatuses = new Set<String>{ 'Completed' };
        for (TaskStatus ts : [SELECT MasterLabel FROM TaskStatus WHERE IsClosed = true]) {
            closedStatuses.add(ts.MasterLabel);
        }

        // ---- Resolve the optional filters into bind values + dynamic WHERE fragments. ----
        Boolean hasFilter = false;

        // Office: narrow to one office plus its own opportunities/contacts.
        Set<Id> officeWhat = new Set<Id>();
        Set<Id> officeWho = new Set<Id>();
        Boolean officeFilter = (officeId != null && accountNameById.containsKey(officeId));
        if (officeFilter) {
            hasFilter = true;
            officeWhat.add(officeId);
            for (Id oId : oppToAccount.keySet()) {
                if (oppToAccount.get(oId) == officeId) { officeWhat.add(oId); }
            }
            for (Id cId : contactToAccount.keySet()) {
                if (contactToAccount.get(cId) == officeId) { officeWho.add(cId); }
            }
        }

        // Team / Legal entity: resolve to the owning users.
        Set<Id> teamOwnerIds = new Set<Id>();
        if (String.isNotBlank(team)) {
            hasFilter = true;
            for (User u : [SELECT Id FROM User WHERE Team__c = :team WITH USER_MODE]) { teamOwnerIds.add(u.Id); }
        }
        Set<Id> legalOwnerIds = new Set<Id>();
        if (String.isNotBlank(legalEntity)) {
            hasFilter = true;
            for (User u : [SELECT Id FROM User WHERE LBR_Legal_Entity__c = :legalEntity WITH USER_MODE]) { legalOwnerIds.add(u.Id); }
        }
        if (ownerId != null) {
            hasFilter = true;
        }
        String likeTerm;
        if (String.isNotBlank(searchTerm)) {
            hasFilter = true;
            likeTerm = '%' + searchTerm + '%';
        }

        List<String> taskConds = new List<String>{
            '(WhatId IN :whatScope OR WhoId IN :whoScope)',
            '(ActivityDate >= :sinceDate OR ActivityDate = null OR Status NOT IN :closedStatuses)'
        };
        List<String> eventConds = new List<String>{
            '(WhatId IN :whatScope OR WhoId IN :whoScope)',
            '(ActivityDate >= :sinceDate OR ActivityDate = null)'
        };
        if (officeFilter) {
            taskConds.add('(WhatId IN :officeWhat OR WhoId IN :officeWho)');
            eventConds.add('(WhatId IN :officeWhat OR WhoId IN :officeWho)');
        }
        if (ownerId != null) {
            taskConds.add('OwnerId = :ownerId');
            eventConds.add('OwnerId = :ownerId');
        }
        if (!teamOwnerIds.isEmpty()) {
            taskConds.add('OwnerId IN :teamOwnerIds');
            eventConds.add('OwnerId IN :teamOwnerIds');
        }
        if (!legalOwnerIds.isEmpty()) {
            taskConds.add('OwnerId IN :legalOwnerIds');
            eventConds.add('OwnerId IN :legalOwnerIds');
        }
        if (likeTerm != null) {
            // Description is a long-text area and isn't filterable in SOQL, so search Subject
            // (and Location for events) — both filterable.
            taskConds.add('Subject LIKE :likeTerm');
            eventConds.add('(Subject LIKE :likeTerm OR Location LIKE :likeTerm)');
        }
        String taskWhere = String.join(taskConds, ' AND ');
        String eventWhere = String.join(eventConds, ' AND ');

        Set<Id> ownerIds = new Set<Id>();

        // 4. Task rows (filtered, capped to the most-recent rowCap).
        String taskQuery =
            'SELECT Id, Subject, TaskSubtype, Type, ActivityDate, Status, Priority, Description, ' +
            'LastModifiedDate, OwnerId, Owner.Name, WhatId, What.Name, WhoId, Who.Name ' +
            'FROM Task WHERE ' + taskWhere + ' ORDER BY ActivityDate DESC NULLS LAST LIMIT :rowCap';
        for (Task t : (List<Task>) Database.query(taskQuery, AccessLevel.USER_MODE)) {
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

        // 5. Event rows (filtered, capped).
        String eventQuery =
            'SELECT Id, Subject, EventSubtype, ActivityDate, StartDateTime, EndDateTime, Location, ' +
            'Meeting_Status__c, Description, LastModifiedDate, OwnerId, Owner.Name, WhatId, What.Name, WhoId, Who.Name ' +
            'FROM Event WHERE ' + eventWhere + ' ORDER BY StartDateTime DESC NULLS LAST LIMIT :rowCap';
        for (Event e : (List<Event>) Database.query(eventQuery, AccessLevel.USER_MODE)) {
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
                SELECT Id, Team__c, LBR_Legal_Entity__c FROM User WHERE Id IN :ownerIds WITH USER_MODE
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

        // True per-type totals for the CURRENT filter set (uncapped aggregate — one row per group,
        // so it isn't limited by the row cap and stays accurate for any firm size or filter).
        String taskAgg = 'SELECT Type tp, TaskSubtype st, COUNT(Id) cnt FROM Task WHERE ' + taskWhere + ' GROUP BY Type, TaskSubtype';
        for (AggregateResult ar : (List<AggregateResult>) Database.query(taskAgg, AccessLevel.USER_MODE)) {
            Integer cnt = (Integer) ar.get('cnt');
            switch on mapTaskType((String) ar.get('st'), (String) ar.get('tp')) {
                when 'Email' { out.totalEmails += cnt; }
                when 'Call' { out.totalCalls += cnt; }
                when else { out.totalTasks += cnt; }
            }
        }
        String eventAgg = 'SELECT COUNT(Id) cnt FROM Event WHERE ' + eventWhere;
        for (AggregateResult ar : (List<AggregateResult>) Database.query(eventAgg, AccessLevel.USER_MODE)) {
            out.totalMeetings = (Integer) ar.get('cnt');
        }
        out.totalAll = out.totalEmails + out.totalCalls + out.totalTasks + out.totalMeetings;
        out.capped = out.totalAll > results.size();

        // Filter dropdown options — the FULL lists across the whole firm (so an owner whose activity
        // is entirely beyond the cap is still selectable). Only needed on the unfiltered load.
        if (!hasFilter) {
            out.filterOptions = buildFilterOptions(accountNameById, accountId, whatScope, whoScope, sinceDate, closedStatuses);
        }
        return out;
    }

    // Distinct filter values across the WHOLE firm scope (not row-capped), for the LWC dropdowns.
    private static FilterOptions buildFilterOptions(
        Map<Id, String> accountNameById, Id firmId,
        Set<Id> whatScope, Set<Id> whoScope, Date sinceDate, Set<String> closedStatuses
    ) {
        FilterOptions opts = new FilterOptions();

        // Offices: every office in the firm hierarchy (exclude the firm account itself), by name.
        for (Id aId : accountNameById.keySet()) {
            if (aId != firmId) {
                opts.offices.add(new Opt(accountNameById.get(aId), aId));
            }
        }
        opts.offices.sort();

        // Owners: everyone who owns in-scope activity (distinct, via aggregate — not row-capped).
        Set<Id> ownerIdSet = new Set<Id>();
        for (AggregateResult ar : [
            SELECT OwnerId oid FROM Task
            WHERE (WhatId IN :whatScope OR WhoId IN :whoScope)
              AND (ActivityDate >= :sinceDate OR ActivityDate = null OR Status NOT IN :closedStatuses)
            WITH USER_MODE GROUP BY OwnerId
        ]) {
            ownerIdSet.add((Id) ar.get('oid'));
        }
        for (AggregateResult ar : [
            SELECT OwnerId oid FROM Event
            WHERE (WhatId IN :whatScope OR WhoId IN :whoScope)
              AND (ActivityDate >= :sinceDate OR ActivityDate = null)
            WITH USER_MODE GROUP BY OwnerId
        ]) {
            ownerIdSet.add((Id) ar.get('oid'));
        }
        if (!ownerIdSet.isEmpty()) {
            Set<String> teamSet = new Set<String>();
            Set<String> legalSet = new Set<String>();
            for (User u : [
                SELECT Id, Name, Team__c, LBR_Legal_Entity__c FROM User WHERE Id IN :ownerIdSet WITH USER_MODE ORDER BY Name
            ]) {
                opts.owners.add(new Opt(u.Name, u.Id));
                if (String.isNotBlank(u.Team__c)) { teamSet.add(u.Team__c); }
                if (String.isNotBlank(u.LBR_Legal_Entity__c)) { legalSet.add(u.LBR_Legal_Entity__c); }
            }
            opts.teams = new List<String>(teamSet);
            opts.teams.sort();
            opts.legalEntities = new List<String>(legalSet);
            opts.legalEntities.sort();
        }
        return opts;
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

    public class TimelineResult {
        @AuraEnabled public List<ActivityWrapper> activities = new List<ActivityWrapper>();
        @AuraEnabled public Integer totalEmails = 0;
        @AuraEnabled public Integer totalCalls = 0;
        @AuraEnabled public Integer totalTasks = 0;
        @AuraEnabled public Integer totalMeetings = 0;
        @AuraEnabled public Integer totalAll = 0;
        @AuraEnabled public Boolean capped = false;
        @AuraEnabled public FilterOptions filterOptions;
    }

    public class FilterOptions {
        @AuraEnabled public List<Opt> offices = new List<Opt>();
        @AuraEnabled public List<Opt> owners = new List<Opt>();
        @AuraEnabled public List<String> teams = new List<String>();
        @AuraEnabled public List<String> legalEntities = new List<String>();
    }

    public class Opt implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Opt(String labelIn, String valueIn) {
            this.label = labelIn;
            this.value = valueIn;
        }
        public Integer compareTo(Object other) {
            Opt o = (Opt) other;
            if (this.label == o.label) { return 0; }
            if (this.label == null) { return -1; }
            if (o.label == null) { return 1; }
            return this.label.compareTo(o.label);
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
