/**
 * One-time (re-runnable) backfill for the Opportunity contact-role flags
 * Has_Contact_Role__c and Has_Complete_Contact_Role__c, using the same
 * completeness logic and Custom Metadata settings as the
 * Check_Completeness_of_Contact_Roles before-save flow.
 *
 * Only Opportunities whose computed flags DIFFER from their stored values are
 * updated, to minimise re-firing Opportunity automation.
 *
 * IMPORTANT: run as a user who holds the Bypass_Contact_Role_Check permission
 * (e.g. System Administrator). The update re-fires the before-save flow, which
 * would otherwise block incomplete opportunities at/above the threshold.
 *
 * Usage (Developer Console / anonymous Apex), recommended small scope:
 *   Database.executeBatch(new ContactRoleCheckRecompute(), 50);
 * Optional custom filter (must be valid SOQL on Opportunity):
 *   Database.executeBatch(new ContactRoleCheckRecompute('IsClosed = false AND Probability >= 50'), 50);
 */
public with sharing class ContactRoleCheckRecompute implements Database.Batchable<SObject>, Database.Stateful {

    public Integer processed = 0;
    public Integer updated = 0;
    public Integer failures = 0;
    private final String whereClause;

    public ContactRoleCheckRecompute() {
        // Default scope matches the flow's stamping scope: open opportunities.
        this.whereClause = 'IsClosed = false';
    }

    public ContactRoleCheckRecompute(String customWhere) {
        this.whereClause = String.isBlank(customWhere) ? 'IsClosed = false' : customWhere;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, AccountId, Has_Contact_Role__c, Has_Complete_Contact_Role__c ' +
            'FROM Opportunity WHERE ' + whereClause
        );
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
        Contact_Role_Check_Setting__mdt s = Contact_Role_Check_Setting__mdt.getInstance('Default');
        Boolean rEmail  = s != null && s.Require_Email__c;
        Boolean rTitle  = s != null && s.Require_Title__c;
        Boolean rFirst  = s != null && s.Require_First_Name__c;
        Boolean rStreet = s != null && s.Require_Mailing_Street__c;
        Boolean rCity   = s != null && s.Require_Mailing_City__c;
        Boolean rAcct   = s != null && s.Require_Account_Billing_Address__c;

        Set<Id> oppIds = new Set<Id>();
        Set<Id> acctIds = new Set<Id>();
        for (Opportunity o : scope) {
            oppIds.add(o.Id);
            if (o.AccountId != null) acctIds.add(o.AccountId);
        }

        // First primary contact role per opportunity.
        Map<Id, Id> oppToContact = new Map<Id, Id>();
        for (OpportunityContactRole ocr : [
            SELECT OpportunityId, ContactId FROM OpportunityContactRole
            WHERE OpportunityId IN :oppIds AND IsPrimary = true
        ]) {
            if (!oppToContact.containsKey(ocr.OpportunityId)) {
                oppToContact.put(ocr.OpportunityId, ocr.ContactId);
            }
        }
        Set<Id> contactIds = new Set<Id>(oppToContact.values());
        contactIds.remove(null);

        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, Email, Title, FirstName, MailingStreet, MailingCity
            FROM Contact WHERE Id IN :contactIds
        ]);
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, BillingStreet, BillingCity, BillingCountry
            FROM Account WHERE Id IN :acctIds
        ]);

        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Opportunity o : scope) {
            processed++;
            Boolean hasPrimary = oppToContact.containsKey(o.Id) && oppToContact.get(o.Id) != null;
            Boolean complete = hasPrimary;
            if (hasPrimary) {
                Contact c = contacts.get(oppToContact.get(o.Id));
                if (c == null) {
                    complete = false;
                } else {
                    if (rEmail  && String.isBlank(c.Email))         complete = false;
                    if (rTitle  && String.isBlank(c.Title))         complete = false;
                    if (rFirst  && String.isBlank(c.FirstName))     complete = false;
                    if (rStreet && String.isBlank(c.MailingStreet)) complete = false;
                    if (rCity   && String.isBlank(c.MailingCity))   complete = false;
                }
                if (rAcct) {
                    Account a = (o.AccountId != null) ? accounts.get(o.AccountId) : null;
                    if (a == null || String.isBlank(a.BillingStreet)
                        || String.isBlank(a.BillingCity) || String.isBlank(a.BillingCountry)) {
                        complete = false;
                    }
                }
            }
            // Only touch records whose flags would actually change.
            if (o.Has_Contact_Role__c != hasPrimary || o.Has_Complete_Contact_Role__c != complete) {
                toUpdate.add(new Opportunity(
                    Id = o.Id,
                    Has_Contact_Role__c = hasPrimary,
                    Has_Complete_Contact_Role__c = complete
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] rs = Database.update(toUpdate, false);
            for (Database.SaveResult r : rs) {
                if (r.isSuccess()) { updated++; } else { failures++; }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('ContactRoleCheckRecompute finished: processed=' + processed
            + ' updated=' + updated + ' failures=' + failures);
    }
}
