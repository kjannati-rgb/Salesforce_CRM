/**
 * LBRInteractionOrphanMonitor
 * ---------------------------
 * Daily watchdog (REV-68). Finds LBR interactions still parented to a CONVERTED Lead — i.e.
 * ones the immediate LeadConvertReparent trigger AND the nightly LBRInteractionConvertSweeper
 * could not move (most commonly because the converted Account is not an Office record type,
 * which the interaction's Account__c lookup filter requires). Emails all active System
 * Administrators only when something is actually stuck (no spam on a clean run).
 *
 * Schedule (e.g. 03:00, after the 02:00 sweeper):
 *   System.schedule('LBR Interaction Orphan Monitor','0 0 3 * * ?', new LBRInteractionOrphanMonitor());
 */
public with sharing class LBRInteractionOrphanMonitor implements Schedulable {

    @TestVisible private static Integer lastCount = 0;

    public void execute(SchedulableContext sc) {
        run();
    }

    public static void run() {
        notify(getStuck());
    }

    @TestVisible
    private static List<LBR_Interactions__c> getStuck() {
        return [
            SELECT Id, Name, Lead__c, Lead__r.Name
            FROM LBR_Interactions__c
            WHERE Lead__c != null AND Lead__r.IsConverted = true
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }

    @TestVisible
    private static void notify(List<LBR_Interactions__c> stuck) {
        lastCount = stuck.size();
        if (stuck.isEmpty()) return;

        List<String> recipients = new List<String>();
        for (User u : [
            SELECT Email FROM User
            WHERE IsActive = true AND Profile.Name = 'System Administrator' AND Email != null
        ]) {
            recipients.add(u.Email);
        }
        if (recipients.isEmpty()) return;

        String body = 'REV-68 monitor: ' + stuck.size() + ' LBR Interaction(s) are still parented to a CONVERTED Lead.\n'
            + 'The immediate re-parent and the nightly sweeper could not move them — most likely the converted '
            + 'Account is not an Office record type (the interaction Account field only accepts Offices).\n\n';
        Integer shown = 0;
        for (LBR_Interactions__c i : stuck) {
            body += '- ' + i.Name + ' (' + i.Id + ') on Lead ' + i.Lead__r.Name + ' (' + i.Lead__c + ')\n';
            if (++shown >= 50) { body += '... and ' + (stuck.size() - shown) + ' more.\n'; break; }
        }
        body += '\nReview: SELECT Id, Lead__c, Account__c FROM LBR_Interactions__c '
            + 'WHERE Lead__c != null AND Lead__r.IsConverted = true';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(recipients);
        mail.setSubject('[REV-68] ' + stuck.size() + ' LBR interaction(s) stuck on converted leads');
        mail.setPlainTextBody(body);
        mail.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LBRInteractionOrphanMonitor email failed: ' + e.getMessage());
        }
    }
}
