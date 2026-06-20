/**
 * Renders a Classic email template against a related record and emails the rendered
 * content to a supplied list of addresses.
 *
 * Why this exists: Salesforce blocks a templated email that carries a record context
 * (WhatId) when the recipient is an internal User ("WhatId is not available for sending
 * emails to UserIds"). The handshake templates merge entirely from Customer_Journey__c,
 * so they need the CJ as WhatId. By rendering the template up front (renderStoredEmailTemplate)
 * and sending the already-merged HTML to plain addresses, the outbound message carries no
 * WhatId, so it can go to any recipient (SDRs / managers) while reusing the existing
 * Classic template verbatim (no duplicate Lightning clone to keep in sync).
 *
 * Send-failure logging: sends use allOrNone=false, so a delivery failure is returned as a
 * failed result rather than thrown (the calling flow's fault path never fires). This class
 * inspects the results and writes a Flow_Log__c row for any failure, so silent failures are
 * observable. (Thrown exceptions, e.g. a render error, are still caught by the flow's fault
 * connector -> Flow_log_v3.)
 *
 * Invoked from the Send_Handshake_SDR_Notification flow.
 */
public with sharing class HandshakeSDRNotifier {

    public class Request {
        @InvocableVariable(label='Related Record Id (Customer Journey)' required=true)
        public String relatedRecordId;

        @InvocableVariable(label='Email Template Developer Name' required=true)
        public String templateDevName;

        @InvocableVariable(label='Recipient Email Addresses' required=true)
        public List<String> recipientEmails;

        @InvocableVariable(label='Org-Wide Email Address (sender)')
        public String orgWideEmailAddress;
    }

    @InvocableMethod(label='Send Handshake Email To Addresses'
        description='Renders a Classic email template against the related record and emails it to the supplied addresses (no WhatId on the outbound message, so it works for any recipient including internal Users). Logs any send failure to Flow_Log__c.')
    public static void send(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        // Bulk lookups so this is safe if ever called with multiple requests.
        Set<String> devNames = new Set<String>();
        Set<String> owaAddrs = new Set<String>();
        for (Request r : requests) {
            if (String.isNotBlank(r.templateDevName)) {
                devNames.add(r.templateDevName);
            }
            if (String.isNotBlank(r.orgWideEmailAddress)) {
                owaAddrs.add(r.orgWideEmailAddress);
            }
        }

        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (EmailTemplate t : [SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :devNames]) {
            templateIdByName.put(t.DeveloperName, t.Id);
        }

        Map<String, Id> owaIdByAddr = new Map<String, Id>();
        if (!owaAddrs.isEmpty()) {
            for (OrgWideEmailAddress o : [SELECT Id, Address FROM OrgWideEmailAddress WHERE Address IN :owaAddrs]) {
                owaIdByAddr.put(o.Address, o.Id);
            }
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Request> sentRequests = new List<Request>(); // parallel to messages, for failure correlation
        for (Request r : requests) {
            if (r.recipientEmails == null || r.recipientEmails.isEmpty()) {
                continue;
            }
            if (String.isBlank(r.relatedRecordId)) {
                continue;
            }
            Id templateId = templateIdByName.get(r.templateDevName);
            if (templateId == null) {
                continue;
            }

            // Render the Classic template against the related record (whatId). whoId is null
            // because the handshake templates do not use {!Recipient...} merge fields.
            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(templateId, null, (Id) r.relatedRecordId);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(r.recipientEmails);
            msg.setSubject(rendered.getSubject());
            if (rendered.getHtmlBody() != null) {
                msg.setHtmlBody(rendered.getHtmlBody());
            }
            if (rendered.getPlainTextBody() != null) {
                msg.setPlainTextBody(rendered.getPlainTextBody());
            }
            // Sending pre-rendered content to addresses: no WhatId, no save-as-activity.
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

        // Capture any failures (returned as results, not thrown) so they are not silent.
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
    private static Flow_Log__c buildFailureLog(Request r, String errText) {
        String recips = (r.recipientEmails == null) ? '' : String.join(r.recipientEmails, ', ');
        String recUrl;
        try {
            recUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + r.relatedRecordId;
        } catch (Exception ignored) {
            recUrl = null;
        }
        return new Flow_Log__c(
            Class_Name__c = 'HandshakeSDRNotifier',
            Flow_Name__c = 'Send_Handshake_SDR_Notification',
            Record_Name__c = ('SDR handshake send failed (template ' + r.templateDevName + ')').abbreviate(255),
            Record_URL__c = (recUrl == null) ? null : recUrl.abbreviate(255),
            Error_Description__c = 'Recipients: ' + recips
                + '\nTemplate: ' + r.templateDevName
                + '\nRelated record: ' + r.relatedRecordId
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
            System.debug(LoggingLevel.ERROR, 'HandshakeSDRNotifier: could not write Flow_Log__c: ' + e.getMessage());
        }
    }
}
