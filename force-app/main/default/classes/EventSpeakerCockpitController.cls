/**
 * EventSpeakerCockpitController
 *
 * Thin @AuraEnabled facade over EventSpeakerCockpitService. Kept deliberately dumb -
 * no business logic here - so the service class stays independently unit-testable
 * and reusable if this ever needs to be called from Agentforce or another channel.
 */
public with sharing class EventSpeakerCockpitController {

    @AuraEnabled(cacheable=true)
    public static List<EventSpeakerCockpitService.EventSummary> getEventsWithSpeakers() {
        try {
            return EventSpeakerCockpitService.getEventsWithSpeakers();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<EventSpeakerCockpitService.SpeakerRosterRow> getRoster(Id campaignId) {
        try {
            return EventSpeakerCockpitService.getRoster(campaignId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getStatusPicklistValues() {
        try {
            return EventSpeakerCockpitService.getStatusPicklistValues();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateStatuses(List<EventSpeakerCockpitService.StatusUpdate> updates) {
        try {
            EventSpeakerCockpitService.updateStatuses(updates);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void bulkToggleField(List<Id> recordIds, String fieldApiName, String newValue) {
        try {
            EventSpeakerCockpitService.bulkToggleField(recordIds, fieldApiName, newValue);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
