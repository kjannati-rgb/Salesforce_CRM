@isTest
private class EventSpeakerCockpitControllerTest {

    @TestSetup
    static void setup() {
        Campaign camp = new Campaign(
            Name = 'Test Conference 2026 ROI',
            StartDate = Date.today().addDays(30),
            EndDate = Date.today().addDays(31),
            Brand__c = 'GAR',
            Status = 'Planned',
            IsActive = true,
            Event_Location__c = 'Test Location'
        );
        insert camp;

        Account acct = new Account(Name = 'Test Speaker Firm');
        insert acct;

        List<Contact> speakers = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            speakers.add(new Contact(
                LastName = 'Speaker' + i,
                Email = 'speaker' + i + '@example.com',
                AccountId = acct.Id
            ));
        }
        insert speakers;

        List<Event_Speaker_Management__c> roster = new List<Event_Speaker_Management__c>();
        List<String> statuses = new List<String>{ 'Lead', 'Pending', 'Confirmed', 'Confirmed', 'Decline' };
        for (Integer i = 0; i < speakers.size(); i++) {
            roster.add(new Event_Speaker_Management__c(
                Speaker__c = speakers[i].Id,
                CampaignEvent__c = camp.Id,
                Speaker_Status__c = statuses[i],
                Speaker_Attendance__c = 'Live',
                Speaker_Type__c = 'Speaker',
                Sponsor__c = 'No'
            ));
        }
        insert roster;
    }

    @isTest
    static void testGetEventsWithSpeakers() {
        Test.startTest();
        List<EventSpeakerCockpitService.EventSummary> events = EventSpeakerCockpitController.getEventsWithSpeakers();
        Test.stopTest();

        System.assertEquals(1, events.size(), 'Expected exactly one event summary.');
        System.assertEquals(5, events[0].totalSpeakers, 'Expected 5 speakers on the test event.');
        System.assertEquals(2, events[0].confirmedCount, 'Expected 2 confirmed speakers.');
    }

    @isTest
    static void testGetRoster() {
        Campaign camp = [SELECT Id FROM Campaign LIMIT 1];

        Test.startTest();
        List<EventSpeakerCockpitService.SpeakerRosterRow> roster = EventSpeakerCockpitController.getRoster(camp.Id);
        Test.stopTest();

        System.assertEquals(5, roster.size(), 'Expected 5 roster rows.');
    }

    @isTest
    static void testGetRosterNullCampaignThrows() {
        Test.startTest();
        try {
            EventSpeakerCockpitController.getRoster(null);
            System.assert(false, 'Expected an exception for a null campaign id.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetStatusPicklistValues() {
        Test.startTest();
        List<String> values = EventSpeakerCockpitController.getStatusPicklistValues();
        Test.stopTest();

        System.assert(values.contains('Confirmed'), 'Expected Confirmed in picklist values.');
        System.assert(values.contains('Lead'), 'Expected Lead in picklist values.');
    }

    @isTest
    static void testUpdateStatuses() {
        List<Event_Speaker_Management__c> roster = [SELECT Id FROM Event_Speaker_Management__c];
        List<EventSpeakerCockpitService.StatusUpdate> updates = new List<EventSpeakerCockpitService.StatusUpdate>();
        for (Event_Speaker_Management__c r : roster) {
            EventSpeakerCockpitService.StatusUpdate su = new EventSpeakerCockpitService.StatusUpdate();
            su.recordId = r.Id;
            su.newStatus = 'Confirmed';
            updates.add(su);
        }

        Test.startTest();
        EventSpeakerCockpitController.updateStatuses(updates);
        Test.stopTest();

        Integer confirmedCount = [SELECT COUNT() FROM Event_Speaker_Management__c WHERE Speaker_Status__c = 'Confirmed'];
        System.assertEquals(5, confirmedCount, 'All records should now be Confirmed.');
    }

    @isTest
    static void testBulkToggleFieldAllowed() {
        List<Id> ids = new List<Id>();
        for (Event_Speaker_Management__c r : [SELECT Id FROM Event_Speaker_Management__c]) {
            ids.add(r.Id);
        }

        Test.startTest();
        EventSpeakerCockpitController.bulkToggleField(ids, 'Received_Bio__c', 'Yes');
        Test.stopTest();

        Integer yesCount = [SELECT COUNT() FROM Event_Speaker_Management__c WHERE Received_Bio__c = 'Yes'];
        System.assertEquals(5, yesCount, 'All records should have Received_Bio__c = Yes.');
    }

    @isTest
    static void testBulkToggleFieldDisallowedFieldThrows() {
        List<Id> ids = new List<Id>();
        for (Event_Speaker_Management__c r : [SELECT Id FROM Event_Speaker_Management__c]) {
            ids.add(r.Id);
        }

        Test.startTest();
        try {
            EventSpeakerCockpitController.bulkToggleField(ids, 'OwnerId', 'someValue');
            System.assert(false, 'Expected an exception for a disallowed field.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testBulkToggleVolumeAtGovernorScale() {
        Campaign camp = [SELECT Id FROM Campaign LIMIT 1];
        Account acct = [SELECT Id FROM Account LIMIT 1];

        List<Contact> speakers = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            speakers.add(new Contact(LastName = 'BulkSpeaker' + i, Email = 'bulk' + i + '@example.com', AccountId = acct.Id));
        }
        insert speakers;

        List<Event_Speaker_Management__c> roster = new List<Event_Speaker_Management__c>();
        for (Contact c : speakers) {
            roster.add(new Event_Speaker_Management__c(
                Speaker__c = c.Id,
                CampaignEvent__c = camp.Id,
                Speaker_Status__c = 'Pending',
                Speaker_Attendance__c = 'Virtual',
                Speaker_Type__c = 'Speaker'
            ));
        }
        insert roster;

        List<Id> ids = new List<Id>();
        for (Event_Speaker_Management__c r : roster) {
            ids.add(r.Id);
        }

        Test.startTest();
        EventSpeakerCockpitController.bulkToggleField(ids, 'Sent_Calendar_Invite__c', 'Yes');
        Test.stopTest();

        Integer yesCount = [
            SELECT COUNT() FROM Event_Speaker_Management__c
            WHERE Sent_Calendar_Invite__c = 'Yes' AND CampaignEvent__c = :camp.Id
        ];
        System.assertEquals(200, yesCount, 'Bulk toggle should handle 200 records in a single call.');
    }
}
