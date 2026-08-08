@isTest
private class OfficeActivityTimelineControllerTest {
    @testSetup
    static void setup() {
        // Ultimate_Account__c (the "Firm Account" lookup) carries a lookup filter: its target
        // must be a "Firm" record-type Account. So the parent has to be created as Firm, or the
        // office insert fails with FIELD_FILTER_VALIDATION_EXCEPTION. Resolve the id by
        // DeveloperName so the test stays org-portable.
        Id firmRecordTypeId = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Firm'
            LIMIT 1
        ].Id;

        Account firm = new Account(Name = 'Test Firm', RecordTypeId = firmRecordTypeId);
        insert firm;

        // Office linked the standard way, and one linked via the custom Firm lookup.
        Account officeParent = new Account(Name = 'Office via ParentId', ParentId = firm.Id);
        Account officeLookup = new Account(Name = 'Office via Ultimate_Account', Ultimate_Account__c = firm.Id);
        insert new List<Account>{ officeParent, officeLookup };

        Contact contact = new Contact(LastName = 'Holloway', AccountId = officeParent.Id);
        insert contact;

        String stageName = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true LIMIT 1].MasterLabel;
        Opportunity opp = new Opportunity(
            Name = 'Renewal 2027',
            AccountId = officeLookup.Id,
            StageName = stageName,
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        List<Task> tasks = new List<Task>{
            // Logged directly against an office account.
            new Task(Subject = 'Re: proposal', TaskSubtype = 'Email', Status = 'Completed',
                     Priority = 'Normal', ActivityDate = Date.today(), WhatId = officeParent.Id),
            // Logged against a contact under an office (WhoId only).
            new Task(Subject = 'Call notes', TaskSubtype = 'Call', Status = 'Completed',
                     Priority = 'Normal', ActivityDate = Date.today(), WhoId = contact.Id),
            // Logged against an opportunity under an office.
            new Task(Subject = 'Send paperwork', Status = 'Completed',
                     Priority = 'Normal', ActivityDate = Date.today(), WhatId = opp.Id),
            // Open + overdue task against a contact.
            new Task(Subject = 'Chase signature', Status = 'Not Started',
                     Priority = 'High', ActivityDate = Date.today().addDays(-2), WhoId = contact.Id)
        };
        insert tasks;

        Event evt = new Event(
            Subject = 'Intro meeting',
            WhatId = officeLookup.Id,
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1),
            IsAllDayEvent = false
        );
        insert evt;
    }

    @isTest
    static void rollsUpAcrossAccountsContactsAndOpps() {
        Account firm = [SELECT Id FROM Account WHERE Name = 'Test Firm' LIMIT 1];

        Test.startTest();
        OfficeActivityTimelineController.TimelineResult result =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, null, null, null, null, null);
        List<OfficeActivityTimelineController.ActivityWrapper> rows = result.activities;
        Test.stopTest();

        System.assertEquals(5, rows.size(), 'Expected 4 tasks + 1 event across accounts, contacts and opportunities');
        System.assertEquals(5, result.totalAll, 'Headline total should count all in-scope activity');
        System.assertEquals(false, result.capped, 'Five rows under the 1000 cap should not be flagged capped');

        Set<String> offices = new Set<String>();
        Boolean sawOpenItem = false;
        Boolean sawOpportunityLink = false;
        for (OfficeActivityTimelineController.ActivityWrapper w : rows) {
            System.assertNotEquals(null, w.officeName, 'Every row should be attributed to an office');
            offices.add(w.officeName);
            if (w.isOpen == true) {
                sawOpenItem = true;
            }
            if (w.relatedToName == 'Renewal 2027') {
                sawOpportunityLink = true;
            }
        }
        System.assert(offices.contains('Office via ParentId'), 'Parent-hierarchy office should be represented');
        System.assert(offices.contains('Office via Ultimate_Account'), 'Custom-lookup office should be represented');
        System.assert(sawOpenItem, 'The open/overdue task should be flagged isOpen = true');
        System.assert(sawOpportunityLink, 'The opportunity-linked task should carry the opportunity name');
    }

    @isTest
    static void handlesNullId() {
        Test.startTest();
        OfficeActivityTimelineController.TimelineResult result =
            OfficeActivityTimelineController.getOfficeActivities(null, 36, 1000, null, null, null, null, null);
        List<OfficeActivityTimelineController.ActivityWrapper> rows = result.activities;
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'A null accountId should return an empty list, not error');
    }

    @isTest
    static void classifiesCallByTypePicklist() {
        // Org convention: a call is a Task with Type = 'Call' (TaskSubtype stays 'Task'),
        // NOT the Log-a-Call subtype. The component must badge it as a Call regardless.
        Account firm = [SELECT Id FROM Account WHERE Name = 'Test Firm' LIMIT 1];
        Account office = [SELECT Id FROM Account WHERE Name = 'Office via ParentId' LIMIT 1];
        insert new Task(Subject = 'Discovery call', Type = 'Call', Status = 'Completed',
                        Priority = 'Normal', ActivityDate = Date.today(), WhatId = office.Id);

        Test.startTest();
        OfficeActivityTimelineController.TimelineResult result =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, null, null, null, null, null);
        List<OfficeActivityTimelineController.ActivityWrapper> rows = result.activities;
        Test.stopTest();

        Boolean sawTypeCall = false;
        for (OfficeActivityTimelineController.ActivityWrapper w : rows) {
            if (w.subject == 'Discovery call') {
                System.assertEquals('Call', w.type, 'A Task with Type=Call should classify as Call');
                sawTypeCall = true;
            }
        }
        System.assert(sawTypeCall, 'The Type=Call task should appear in the rollup');
    }

    @isTest
    static void meetingUsesMeetingStatusField() {
        // Events have no Task.Status; the component surfaces Meeting_Status__c, labelled "Meeting Status".
        Account firm = [SELECT Id FROM Account WHERE Name = 'Test Firm' LIMIT 1];
        Account office = [SELECT Id FROM Account WHERE Name = 'Office via ParentId' LIMIT 1];
        insert new Event(
            Subject = 'Kickoff meeting',
            WhatId = office.Id,
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1),
            Meeting_Status__c = 'Scheduled'
        );

        Test.startTest();
        OfficeActivityTimelineController.TimelineResult result =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, null, null, null, null, null);
        List<OfficeActivityTimelineController.ActivityWrapper> rows = result.activities;
        Test.stopTest();

        Boolean checked = false;
        for (OfficeActivityTimelineController.ActivityWrapper w : rows) {
            if (w.subject == 'Kickoff meeting') {
                System.assertEquals('Scheduled', w.status, 'Event status should come from Meeting_Status__c');
                System.assertEquals('Meeting Status', w.statusLabel, 'Event status should be labelled Meeting Status');
                checked = true;
            }
        }
        System.assert(checked, 'The meeting should appear in the rollup');
    }

    @isTest
    static void filtersServerSide() {
        // The structured filters are applied in SOQL so they reach activity beyond the row cap.
        Account firm = [SELECT Id FROM Account WHERE Name = 'Test Firm' LIMIT 1];
        Account office = [SELECT Id FROM Account WHERE Name = 'Office via ParentId' LIMIT 1];

        Test.startTest();
        // Search: only the proposal task matches.
        OfficeActivityTimelineController.TimelineResult bySearch =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, null, null, null, null, 'proposal');
        // Owner: the running user owns all the test activity.
        OfficeActivityTimelineController.TimelineResult byOwner =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, null, UserInfo.getUserId(), null, null, null);
        // Office: only the ParentId office's activity.
        OfficeActivityTimelineController.TimelineResult byOffice =
            OfficeActivityTimelineController.getOfficeActivities(firm.Id, 36, 1000, office.Id, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, bySearch.activities.size(), 'Search should return only the matching task');
        System.assertEquals('Re: proposal', bySearch.activities[0].subject);
        System.assertEquals(1, bySearch.totalAll, 'Filtered totals should reflect the search');

        System.assertEquals(5, byOwner.activities.size(), 'Owner = current user returns all test activity');

        System.assert(!byOffice.activities.isEmpty(), 'Office filter should return that office\'s activity');
        for (OfficeActivityTimelineController.ActivityWrapper w : byOffice.activities) {
            System.assertEquals('Office via ParentId', w.officeName, 'Office filter should only return that office');
        }
    }
}
