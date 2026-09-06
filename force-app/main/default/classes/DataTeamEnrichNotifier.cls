/**
 * Sends the "Account is not complete" alert to the Data Team with a dynamic list of the
 * fields that are actually missing.
 *
 * Why this replaced the Email Alert: the previous implementation called the classic
 * Email Alert Opportunity.Data_Team_Enrich_Account, which only accepts an SObjectRowId.
 * There is no way to pass a per-record value (the missing-field list) into a classic
 * alert, so the email always said "Billing Country, City & Street" regardless of which
 * of the three were actually blank. This class keeps the HTML in the Classic template
 * (so it stays editable outside code, alongside the rest of the Centellic estate) and
 * substitutes a literal [[MISSING_FIELDS]] token after render.
 *
 * Why it renders against the Account and not the Opportunity: the template merges only
 * {!Account.Name}, {!Account.Salesforce_Account_ID__c} and {!Account.Link}. Rendering
 * with the Account as whatId resolves all three directly rather than relying on
 * cross-object traversal from an Opportunity context.
 *
 * Recipients are resolved from a public group at send time, and INACTIVE members are
 * dropped. The Data_Team group carries dormant members (7 of 16 at time of writing);
 * the classic alert would have started mailing them again the moment they were
 * reactivated. See [[MISSING_FIELDS]] token contract in Data_Team_Enrich_Account.
 *
 * Send-failure logging follows HandshakeSDRNotifier: sends use allOrNone=false, so a
 * delivery failure comes back as a failed result rather than thrown, and the calling
 * flow's fault path never fires. Failures are written to Flow_Log__c so they are not
 * silent. Thrown exceptions (e.g. a render error) still hit the flow's fault connector.
 *
 * Invoked from the Opportunity master flow.
 */
public with sharing class DataTeamEnrichNotifier {

    @TestVisible
    private static final String MISSING_TOKEN = '[[MISSING_FIELDS]]';

    public class Request {
        @InvocableVariable(label='Related Record Id (Account)' required=true)
        public String relatedRecordId;

        @InvocableVariable(label='Email Template Developer Name' required=true)
        public String templateDevName;

        @InvocableVariable(label='Recipient Public Group Developer Name' required=true)
        public String recipientGroupDevName;

        @InvocableVariable(label='Missing Fields (comma separated)')
        public String missingFields;

        @InvocableVariable(label='Org-Wide Email Address (sender)')
        public String orgWideEmailAddress;
    }

    @InvocableMethod(label='Send Data Team Account Enrichment Alert'
        description='Renders a Classic email template against the Account, substitutes the [[MISSING_FIELDS]] token with the supplied list, and emails it to the active members of the given public group. Logs any send failure to Flow_Log__c.')
    public static void send(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        // Bulk lookups first: the master flow is record-triggered, so a bulk Opportunity
        // insert calls this once with many requests.
        Set<String> devNames = new Set<String>();
        Set<String> groupNames = new Set<String>();
        Set<String> owaAddrs = new Set<String>();
        for (Request r : requests) {
            if (String.isNotBlank(r.templateDevName)) {
                devNames.add(r.templateDevName);
            }
            if (String.isNotBlank(r.recipientGroupDevName)) {
                groupNames.add(r.recipientGroupDevName);
            }
            if (String.isNotBlank(r.orgWideEmailAddress)) {
                owaAddrs.add(r.orgWideEmailAddress);
            }
        }

        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (EmailTemplate t : [SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :devNames]) {
            templateIdByName.put(t.DeveloperName, t.Id);
        }

        Map<String, List<String>> recipientsByGroup = resolveActiveGroupMembers(groupNames);

        Map<String, Id> owaIdByAddr = new Map<String, Id>();
        if (!owaAddrs.isEmpty()) {
            for (OrgWideEmailAddress o : [SELECT Id, Address FROM OrgWideEmailAddress WHERE Address IN :owaAddrs]) {
                owaIdByAddr.put(o.Address, o.Id);
            }
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Request> sentRequests = new List<Request>(); // parallel to messages, for failure correlation
        for (Request r : requests) {
            if (String.isBlank(r.relatedRecordId)) {
                continue;
            }
            Id templateId = templateIdByName.get(r.templateDevName);
            if (templateId == null) {
                continue;
            }
            List<String> toAddresses = recipientsByGroup.get(r.recipientGroupDevName);
            if (toAddresses == null || toAddresses.isEmpty()) {
                continue;
            }

            // whoId is null: the template carries no {!Recipient...} merge fields.
            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(templateId, null, (Id) r.relatedRecordId);

            String missing = String.isBlank(r.missingFields) ? 'Not specified' : r.missingFields;

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toAddresses);
            msg.setSubject(substitute(rendered.getSubject(), missing));
            if (rendered.getHtmlBody() != null) {
                msg.setHtmlBody(substitute(rendered.getHtmlBody(), missing));
            }
            if (rendered.getPlainTextBody() != null) {
                msg.setPlainTextBody(substitute(rendered.getPlainTextBody(), missing));
            }
            // Pre-rendered content sent to plain addresses: no WhatId, no save-as-activity.
            msg.setSaveAsActivity(false);

            if (String.isNotBlank(r.orgWideEmailAddress) && owaIdByAddr.containsKey(r.orgWideEmailAddress)) {
                msg.setOrgWideEmailAddressId(owaIdByAddr.get(r.orgWideEmailAddress));
            }
            messages.add(msg);
            sentRequests.add(r);
        }

        if (messages.isEmpty()) {
            return;
        }

        // allOrNone = false: a bad address for one recipient should not block the rest.
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);

        List<Flow_Log__c> failures = new List<Flow_Log__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String errText = '';
                for (Messaging.SendEmailError err : results[i].getErrors()) {
                    errText += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                }
                failures.add(buildFailureLog(sentRequests[i], errText));
            }
        }
        logFailures(failures);
    }

    @TestVisible
    private static String substitute(String body, String missing) {
        return (body == null) ? null : body.replace(MISSING_TOKEN, missing);
    }

    /**
     * Resolves each public group to the email addresses of its ACTIVE direct user members.
     * Nested groups and roles are not expanded - Data_Team holds only direct user members,
     * and silently mailing an entire nested role hierarchy would be worse than under-sending.
     */
    @TestVisible
    private static Map<String, List<String>> resolveActiveGroupMembers(Set<String> groupNames) {
        Map<String, List<String>> result = new Map<String, List<String>>();
        if (groupNames == null || groupNames.isEmpty()) {
            return result;
        }

        Map<Id, String> groupNameById = new Map<Id, String>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :groupNames AND Type = 'Regular']) {
            groupNameById.put(g.Id, g.DeveloperName);
        }
        if (groupNameById.isEmpty()) {
            return result;
        }

        Map<Id, Set<Id>> userIdsByGroup = new Map<Id, Set<Id>>();
        Set<Id> allUserIds = new Set<Id>();
        for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :groupNameById.keySet()]) {
            // Only direct User members; nested Group/Role ids are skipped by design.
            if (gm.UserOrGroupId.getSobjectType() != User.SObjectType) {
                continue;
            }
            if (!userIdsByGroup.containsKey(gm.GroupId)) {
                userIdsByGroup.put(gm.GroupId, new Set<Id>());
            }
            userIdsByGroup.get(gm.GroupId).add(gm.UserOrGroupId);
            allUserIds.add(gm.UserOrGroupId);
        }
        if (allUserIds.isEmpty()) {
            return result;
        }

        Map<Id, String> emailByActiveUser = new Map<Id, String>();
        for (User u : [SELECT Id, Email FROM User WHERE Id IN :allUserIds AND IsActive = true AND Email != null]) {
            emailByActiveUser.put(u.Id, u.Email);
        }

        for (Id groupId : userIdsByGroup.keySet()) {
            Set<String> addrs = new Set<String>(); // dedupe: a user can appear once per group only, but be safe
            for (Id userId : userIdsByGroup.get(groupId)) {
                if (emailByActiveUser.containsKey(userId)) {
                    addrs.add(emailByActiveUser.get(userId));
                }
            }
            if (!addrs.isEmpty()) {
                result.put(groupNameById.get(groupId), new List<String>(addrs));
            }
        }
        return result;
    }

    @TestVisible
    private static Flow_Log__c buildFailureLog(Request r, String errText) {
        List<String> recipients = resolveActiveGroupMembers(new Set<String>{ r.recipientGroupDevName })
            .get(r.recipientGroupDevName);
        String recips = (recipients == null) ? '' : String.join(recipients, ', ');
        String recUrl;
        try {
            recUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + r.relatedRecordId;
        } catch (Exception ignored) {
            recUrl = null;
        }
        return new Flow_Log__c(
            Class_Name__c = 'DataTeamEnrichNotifier',
            Flow_Name__c = 'Opportunity',
            Record_Name__c = ('Data Team enrichment alert send failed (template ' + r.templateDevName + ')').abbreviate(255),
            Record_URL__c = (recUrl == null) ? null : recUrl.abbreviate(255),
            Error_Description__c = 'Recipients: ' + recips
                + '\nTemplate: ' + r.templateDevName
                + '\nGroup: ' + r.recipientGroupDevName
                + '\nAccount: ' + r.relatedRecordId
                + '\nMissing: ' + r.missingFields
                + '\nErrors:\n' + errText,
            Interview_Start_Time__c = Datetime.now()
        );
    }

    @TestVisible
    private static void logFailures(List<Flow_Log__c> failures) {
        if (failures == null || failures.isEmpty()) {
            return;
        }
        try {
            insert failures;
        } catch (Exception e) {
            // Best-effort logging: never let a logging hiccup break the email feature.
            System.debug(LoggingLevel.ERROR, 'DataTeamEnrichNotifier: could not write Flow_Log__c: ' + e.getMessage());
        }
    }
}
