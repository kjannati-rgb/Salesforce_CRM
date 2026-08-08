/**
 * EventSpeakerCockpitService
 *
 * Business logic and data access layer for the Event Speaker Management cockpit.
 * Anchored on Campaign (CampaignEvent__c) per the move off Cvent to Campaign-native
 * events. Consumed by the production roster board LWC today; designed to be reused
 * by lighter marketing (Campaign record page) and sales (Account/Contact) panels
 * as compact views over the same service, per the agreed one-service/three-views model.
 *
 * Deploy target: KJDEV sandbox first. Do not deploy to production without explicit
 * confirmation.
 */
public with sharing class EventSpeakerCockpitService {

    // Explicit allowlist of readiness/checklist fields that can be bulk-toggled from
    // the cockpit. Never accept an arbitrary client-supplied field API name here -
    // this is the control that stops a compromised/rogue client from writing to
    // fields outside this object's operational checklist (e.g. OwnerId, Speaker__c).
    private static final Set<String> ALLOWED_TOGGLE_FIELDS = new Set<String>{
        'Received_Bio__c',
        'Received_Photo__c',
        'Sent_Calendar_Invite__c',
        'Sent_Thank_You_Email__c',
        'Arranged_pre_panel_call__c',
        'Sent_Pre_Conference_Briefing__c',
        'Updated_Agenda__c',
        'Updated_Website__c',
        'Updated_Marketing__c',
        'Speaker_Ticket_Applicable__c'
    };

    public class CockpitException extends Exception {}

    // ---------- Wrapper types ----------

    public class EventSummary {
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String campaignName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String brand;
        @AuraEnabled public String status;
        @AuraEnabled public Integer totalSpeakers;
        @AuraEnabled public Integer confirmedCount;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer leadCount;
        @AuraEnabled public Integer noResponseCount;
        @AuraEnabled public Integer declineCount;
        @AuraEnabled public Integer cancelledCount;
    }

    public class SpeakerRosterRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Id speakerId;
        @AuraEnabled public String speakerName;
        @AuraEnabled public String speakerEmail;
        @AuraEnabled public String jobTitle;
        @AuraEnabled public String accountName;
        @AuraEnabled public String status;
        @AuraEnabled public String speakerType;
        @AuraEnabled public String session;
        @AuraEnabled public Datetime sessionDateTime;
        @AuraEnabled public String attendance;
        @AuraEnabled public String sponsor;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String receivedBio;
        @AuraEnabled public String receivedPhoto;
        @AuraEnabled public String sentCalendarInvite;
        @AuraEnabled public String sentThankYou;
        @AuraEnabled public String arrangedPrePanelCall;
        @AuraEnabled public String sentPreConferenceBriefing;
        @AuraEnabled public String updatedAgenda;
        @AuraEnabled public String updatedWebsite;
        @AuraEnabled public String updatedMarketing;
        @AuraEnabled public String speakerFee;
        @AuraEnabled public Date lastContactDate;
    }

    public class StatusUpdate {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String newStatus;
    }

    // ---------- Read operations ----------

    /**
     * One row per Campaign that has at least one speaker record, with status
     * counts pre-aggregated server-side. Backs the event picker and the summary
     * chips at the top of the cockpit.
     */
    public static List<EventSummary> getEventsWithSpeakers() {
        List<AggregateResult> counts = [
            SELECT CampaignEvent__c campId, Speaker_Status__c status, COUNT(Id) cnt
            FROM Event_Speaker_Management__c
            WHERE CampaignEvent__c != null
            WITH SECURITY_ENFORCED
            GROUP BY CampaignEvent__c, Speaker_Status__c
        ];

        Set<Id> campaignIds = new Set<Id>();
        for (AggregateResult ar : counts) {
            campaignIds.add((Id) ar.get('campId'));
        }

        if (campaignIds.isEmpty()) {
            return new List<EventSummary>();
        }

        Map<Id, EventSummary> byCampaign = new Map<Id, EventSummary>();
        for (Campaign c : [
            SELECT Id, Name, StartDate, EndDate, Brand__c, Status
            FROM Campaign
            WHERE Id IN :campaignIds
            WITH SECURITY_ENFORCED
        ]) {
            EventSummary es = new EventSummary();
            es.campaignId = c.Id;
            es.campaignName = c.Name;
            es.startDate = c.StartDate;
            es.endDate = c.EndDate;
            es.brand = c.Brand__c;
            es.status = c.Status;
            es.totalSpeakers = 0;
            es.confirmedCount = 0;
            es.pendingCount = 0;
            es.leadCount = 0;
            es.noResponseCount = 0;
            es.declineCount = 0;
            es.cancelledCount = 0;
            byCampaign.put(c.Id, es);
        }

        for (AggregateResult ar : counts) {
            Id campId = (Id) ar.get('campId');
            EventSummary es = byCampaign.get(campId);
            if (es == null) {
                continue;
            }
            Integer cnt = (Integer) ar.get('cnt');
            String status = (String) ar.get('status');
            es.totalSpeakers += cnt;
            if (status == 'Confirmed') {
                es.confirmedCount = cnt;
            } else if (status == 'Pending') {
                es.pendingCount = cnt;
            } else if (status == 'Lead') {
                es.leadCount = cnt;
            } else if (status == 'No Response') {
                es.noResponseCount = cnt;
            } else if (status == 'Decline') {
                es.declineCount = cnt;
            } else if (status == 'Cancelled') {
                es.cancelledCount = cnt;
            }
        }

        return byCampaign.values();
    }

    /**
     * Full roster for a single event (Campaign), decorated with everything the
     * readiness scorecard needs. Sorting/grouping by status happens client-side
     * in the LWC so the board can re-render instantly on local mutation.
     */
    public static List<SpeakerRosterRow> getRoster(Id campaignId) {
        if (campaignId == null) {
            throw new CockpitException('An event must be selected.');
        }

        List<SpeakerRosterRow> rows = new List<SpeakerRosterRow>();

        for (Event_Speaker_Management__c esm : [
            SELECT Id, Speaker__c, Speaker__r.Name, Speaker__r.Email, Job_Title__c,
                   Account_Name__c, Speaker_Status__c, Speaker_Type__c, Session__c,
                   Session_Date_Time__c, Speaker_Attendance__c, Sponsor__c,
                   OwnerId, Owner.Name, Received_Bio__c, Received_Photo__c,
                   Sent_Calendar_Invite__c, Sent_Thank_You_Email__c,
                   Arranged_pre_panel_call__c, Sent_Pre_Conference_Briefing__c,
                   Updated_Agenda__c, Updated_Website__c, Updated_Marketing__c,
                   Speaker_Fee__c, Last_Contact_Date__c
            FROM Event_Speaker_Management__c
            WHERE CampaignEvent__c = :campaignId
            WITH SECURITY_ENFORCED
            ORDER BY Speaker__r.Name ASC
        ]) {
            SpeakerRosterRow row = new SpeakerRosterRow();
            row.recordId = esm.Id;
            row.speakerId = esm.Speaker__c;
            row.speakerName = esm.Speaker__r != null ? esm.Speaker__r.Name : null;
            row.speakerEmail = esm.Speaker__r != null ? esm.Speaker__r.Email : null;
            row.jobTitle = esm.Job_Title__c;
            row.accountName = esm.Account_Name__c;
            row.status = esm.Speaker_Status__c;
            row.speakerType = esm.Speaker_Type__c;
            row.session = esm.Session__c;
            row.sessionDateTime = esm.Session_Date_Time__c;
            row.attendance = esm.Speaker_Attendance__c;
            row.sponsor = esm.Sponsor__c;
            row.ownerId = esm.OwnerId;
            row.ownerName = esm.Owner != null ? esm.Owner.Name : null;
            row.receivedBio = esm.Received_Bio__c;
            row.receivedPhoto = esm.Received_Photo__c;
            row.sentCalendarInvite = esm.Sent_Calendar_Invite__c;
            row.sentThankYou = esm.Sent_Thank_You_Email__c;
            row.arrangedPrePanelCall = esm.Arranged_pre_panel_call__c;
            row.sentPreConferenceBriefing = esm.Sent_Pre_Conference_Briefing__c;
            row.updatedAgenda = esm.Updated_Agenda__c;
            row.updatedWebsite = esm.Updated_Website__c;
            row.updatedMarketing = esm.Updated_Marketing__c;
            row.speakerFee = esm.Speaker_Fee__c;
            row.lastContactDate = esm.Last_Contact_Date__c;
            rows.add(row);
        }
        return rows;
    }

    /** Drives the status columns/move menu from the live picklist, not a hardcoded list. */
    public static List<String> getStatusPicklistValues() {
        List<String> values = new List<String>();
        Schema.DescribeFieldResult fr = Event_Speaker_Management__c.Speaker_Status__c.getDescribe();
        for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
            if (pe.isActive()) {
                values.add(pe.getValue());
            }
        }
        return values;
    }

    // ---------- Write operations ----------

    /** Bulk status change - used by both single-card moves and any future multi-select bar. */
    public static void updateStatuses(List<StatusUpdate> updates) {
        if (updates == null || updates.isEmpty()) {
            return;
        }

        if (!Event_Speaker_Management__c.Speaker_Status__c.getDescribe().isUpdateable()) {
            throw new CockpitException('You do not have permission to update Speaker Status.');
        }

        Map<Id, String> newStatusByRecordId = new Map<Id, String>();
        for (StatusUpdate su : updates) {
            if (su.recordId == null || String.isBlank(su.newStatus)) {
                continue;
            }
            newStatusByRecordId.put(su.recordId, su.newStatus);
        }

        if (newStatusByRecordId.isEmpty()) {
            return;
        }

        List<Event_Speaker_Management__c> toUpdate = new List<Event_Speaker_Management__c>();
        for (Id recId : newStatusByRecordId.keySet()) {
            toUpdate.add(new Event_Speaker_Management__c(
                Id = recId,
                Speaker_Status__c = newStatusByRecordId.get(recId)
            ));
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /**
     * Generic bulk toggle for the readiness/checklist fields (bio, photo, calendar
     * invite, briefing, thank you, etc). This is the fix for the adoption problem:
     * one call can flip the same field across every selected/visible speaker instead
     * of forcing a coordinator to open records one at a time.
     */
    public static void bulkToggleField(List<Id> recordIds, String fieldApiName, String newValue) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new CockpitException('No records selected.');
        }
        if (!ALLOWED_TOGGLE_FIELDS.contains(fieldApiName)) {
            throw new CockpitException('Field is not permitted for bulk update: ' + fieldApiName);
        }

        Schema.DescribeFieldResult fr = Event_Speaker_Management__c.getSObjectType()
            .getDescribe().fields.getMap().get(fieldApiName).getDescribe();
        if (!fr.isUpdateable()) {
            throw new CockpitException('You do not have permission to update ' + fr.getLabel() + '.');
        }

        List<Event_Speaker_Management__c> toUpdate = new List<Event_Speaker_Management__c>();
        for (Id recId : recordIds) {
            Event_Speaker_Management__c rec = new Event_Speaker_Management__c(Id = recId);
            rec.put(fieldApiName, newValue);
            toUpdate.add(rec);
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }
}
