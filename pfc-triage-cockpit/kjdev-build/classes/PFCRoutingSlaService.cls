/**
 * PFC Triage Cockpit — Phase B1 routing safety net.
 *
 * Flags Pardot_Form_Completion__c records that have sat in the PFC Triage Queue
 * beyond the configured working-hours SLA (PFC_Settings__mdt.Default) and posts a
 * digest to the configured Chatter group. Working hours are computed against the
 * org default BusinessHours. Fail-open throughout: an error is logged to
 * Flow_Log__c and never rethrown, so the scheduled job keeps its schedule.
 *
 * Salesforce is the safety net here, not the router: Clay (when its return leg
 * exists) overwrites queue ownership with a real rep; this sweep only makes
 * unrouted records visible.
 */
public with sharing class PFCRoutingSlaService {

    public static final String QUEUE_DEV_NAME = 'PFC_Triage_Queue';
    private static final Integer CHATTER_LINK_LIMIT = 10;

    public class SweepResult {
        public Integer candidates = 0;
        public Integer flagged = 0;
        public Boolean chatterPosted = false;
        public Boolean skipped = false;
    }

    /** Entry point used by the hourly schedulable. Reads all config from CMDT. */
    public static SweepResult run() {
        return run(null, null);
    }

    /** @TestVisible overload: overrides bypass the CMDT (incl. the kill switch) so tests control thresholds. */
    @TestVisible
    private static SweepResult run(Decimal slaHoursOverride, String chatterGroupOverride) {
        SweepResult result = new SweepResult();
        try {
            PFC_Settings__mdt settings = PFC_Settings__mdt.getInstance('Default');
            Boolean usingOverrides = slaHoursOverride != null;
            if (!usingOverrides && (settings == null || settings.Sweep_Disabled__c)) {
                result.skipped = true;
                return result;
            }
            Decimal slaHours = usingOverrides
                ? slaHoursOverride
                : settings.Routing_SLA_Hours__c;
            if (slaHours == null) {
                slaHours = 4;
            }
            String groupName = chatterGroupOverride != null
                ? chatterGroupOverride
                : (settings != null ? settings.Alert_Chatter_Group__c : null);

            List<Group> queues = [
                SELECT Id FROM Group
                WHERE DeveloperName = :QUEUE_DEV_NAME AND Type = 'Queue'
                LIMIT 1
            ];
            if (queues.isEmpty()) {
                logFault('Queue ' + QUEUE_DEV_NAME + ' not found — sweep cannot run.');
                result.skipped = true;
                return result;
            }
            Id queueId = queues[0].Id;

            List<BusinessHours> bhList = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];
            Id bhId = bhList.isEmpty() ? null : bhList[0].Id;

            List<Pardot_Form_Completion__c> candidates = [
                SELECT Id, Name, CreatedDate
                FROM Pardot_Form_Completion__c
                WHERE OwnerId = :queueId AND Routing_Overdue__c = false
                ORDER BY CreatedDate ASC
                LIMIT 9500
            ];
            result.candidates = candidates.size();

            Long slaMillis = (Long) (slaHours * 60 * 60 * 1000);
            DateTime nowDt = System.now();
            List<Pardot_Form_Completion__c> overdue = new List<Pardot_Form_Completion__c>();
            for (Pardot_Form_Completion__c pfc : candidates) {
                Long elapsed = bhId != null
                    ? BusinessHours.diff(bhId, pfc.CreatedDate, nowDt)
                    : (nowDt.getTime() - pfc.CreatedDate.getTime());
                if (elapsed >= slaMillis) {
                    overdue.add(new Pardot_Form_Completion__c(Id = pfc.Id, Routing_Overdue__c = true));
                }
            }

            if (!overdue.isEmpty()) {
                for (Database.SaveResult sr : Database.update(overdue, false)) {
                    if (sr.isSuccess()) {
                        result.flagged++;
                    }
                }
                result.chatterPosted = postDigest(groupName, result.flagged, slaHours, overdue);
            }
        } catch (Exception e) {
            logFault(e.getTypeName() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }
        return result;
    }

    private static Boolean postDigest(String groupName, Integer flaggedCount, Decimal slaHours, List<Pardot_Form_Completion__c> overdue) {
        if (String.isBlank(groupName) || flaggedCount == 0) {
            return false;
        }
        List<CollaborationGroup> groups = [
            SELECT Id FROM CollaborationGroup WHERE Name = :groupName LIMIT 1
        ];
        if (groups.isEmpty()) {
            logFault('Chatter group "' + groupName + '" not found — ' + flaggedCount + ' record(s) flagged without alert.');
            return false;
        }
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<String> lines = new List<String>{
            'PFC Routing SLA breach: ' + flaggedCount + ' form completion(s) have waited more than '
            + slaHours.stripTrailingZeros().toPlainString() + ' working hours in the PFC Triage Queue without being routed to a rep.'
        };
        for (Integer i = 0; i < overdue.size() && i < CHATTER_LINK_LIMIT; i++) {
            lines.add(baseUrl + '/' + overdue[i].Id);
        }
        if (overdue.size() > CHATTER_LINK_LIMIT) {
            lines.add('… and ' + (overdue.size() - CHATTER_LINK_LIMIT) + ' more (see the Routing Overdue list view).');
        }
        insert new FeedItem(
            ParentId = groups[0].Id,
            Body = String.join(lines, '\n'),
            Type = 'TextPost'
        );
        return true;
    }

    private static void logFault(String message) {
        try {
            insert new Flow_Log__c(
                Class_Name__c = 'PFCRoutingSlaService',
                Flow_Name__c = 'PFC_Routing_SLA_Sweep',
                Error_Description__c = message.abbreviate(255),
                Record_Name__c = 'SLA Sweep'
            );
        } catch (Exception ignored) {
            // fail-open: logging must never break the sweep
        }
    }
}
