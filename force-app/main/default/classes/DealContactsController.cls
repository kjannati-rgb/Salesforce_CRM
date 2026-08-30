/**
 * Backs the dealContacts LWC. Reads/writes the five Quote-level contact
 * roles (Primary, Invoice, Creative, Event Logistics, Signatory) and keeps
 * a matching OpportunityContactRole in sync using this org's existing Role
 * picklist values (Decision Maker / Invoice Recipient / Creative Contact /
 * Event Logistical Contact / Insertion Order Signer) - no new fields required.
 *
 * Signatory Contact has its own existing default (Quote_Stamp_Order_Form_Fields
 * fills it from SBQQ__PrimaryContact__c when blank, and only when blank) -
 * this panel just gives a rep visibility into it and a way to override it
 * before that flow ever runs. No Opportunity-field sync: Signatory_Contact__c
 * has no Opportunity-level counterpart, unlike Invoice Contact.
 *
 * Invoice Contact also syncs to Opportunity.Invoice_Contact__c, but only
 * when the edited Quote is the Opportunity's primary quote (SBQQ__Primary__c)
 * - matching the one existing mechanism that already reads this field
 * (Opportunity_BeforeSaveFlow reads SBQQ__PrimaryQuote__r.Invoice_Contact__c),
 * so a non-primary quote's edits never overwrite the Opportunity's value.
 * Primary Contact's own Opportunity sync is handled by the org's existing
 * Opportunity_Contact_Role_Create flow, not by this controller.
 */
public with sharing class DealContactsController {

    private static final Map<String, String> FIELD_BY_ROLE = new Map<String, String>{
        'primary' => 'SBQQ__PrimaryContact__c',
        'invoice' => 'Invoice_Contact__c',
        'creative' => 'Creative_Contact__c',
        'event' => 'Event_Logistics_Contact__c',
        'signatory' => 'Signatory_Contact__c'
    };

    private static final Map<String, String> OCR_ROLE_BY_KEY = new Map<String, String>{
        'primary' => 'Decision Maker',
        'invoice' => 'Invoice Recipient',
        'creative' => 'Creative Contact',
        'event' => 'Event Logistical Contact',
        'signatory' => 'Insertion Order Signer'
    };

    public class ContactRoleInfo {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String source; // synced | renewal | same-as-primary | manual | null
    }

    public class PanelData {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isRenewal;
        @AuraEnabled public Boolean hasAlmEvent;
        @AuraEnabled public Id previousQuoteId;
        @AuraEnabled public String previousQuoteLabel;
        @AuraEnabled public Map<String, ContactRoleInfo> roles;
    }

    public class ContactSearchResult {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean sameOffice;
    }

    @AuraEnabled(cacheable=true)
    public static PanelData getPanelData(Id quoteId) {
        SBQQ__Quote__c q = queryQuote(quoteId);

        PanelData data = new PanelData();
        data.quoteId = q.Id;
        data.accountId = q.SBQQ__Account__c;
        data.accountName = q.SBQQ__Account__r != null ? q.SBQQ__Account__r.Name : null;
        data.isRenewal = q.SBQQ__Type__c == 'Renewal';
        data.hasAlmEvent = q.ALM_Event_Product__c != null && q.ALM_Event_Product__c > 0;

        Map<String, Id> ocrContactByRole = ocrContactsByRole(q.SBQQ__Opportunity2__c);

        data.roles = new Map<String, ContactRoleInfo>{
            'primary' => buildRoleInfo(q.SBQQ__PrimaryContact__c, q.SBQQ__PrimaryContact__r, ocrContactByRole, 'primary'),
            'invoice' => buildRoleInfo(q.Invoice_Contact__c, q.Invoice_Contact__r, ocrContactByRole, 'invoice'),
            'creative' => buildRoleInfo(q.Creative_Contact__c, q.Creative_Contact__r, ocrContactByRole, 'creative'),
            'event' => buildRoleInfo(q.Event_Logistics_Contact__c, q.Event_Logistics_Contact__r, ocrContactByRole, 'event'),
            'signatory' => buildRoleInfo(q.Signatory_Contact__c, q.Signatory_Contact__r, ocrContactByRole, 'signatory')
        };

        if (q.SBQQ__Opportunity2__r != null && q.SBQQ__Opportunity2__r.Previous_Opportunity__c != null) {
            SBQQ__Quote__c prevQuote = findPrimaryQuoteForOpportunity(q.SBQQ__Opportunity2__r.Previous_Opportunity__c);
            if (prevQuote != null) {
                data.previousQuoteId = prevQuote.Id;
                data.previousQuoteLabel = prevQuote.Name;
            }
        }

        return data;
    }

    @AuraEnabled
    public static void setRoleContact(Id quoteId, String role, Id contactId, String source) {
        if (!FIELD_BY_ROLE.containsKey(role)) {
            throw new AuraHandledException('Unknown contact role: ' + role);
        }

        SBQQ__Quote__c q = queryQuoteForWrite(quoteId);
        applyRoleWrite(q, role, contactId);
    }

    @AuraEnabled
    public static Map<String, Id> copyFromPreviousQuote(Id quoteId) {
        SBQQ__Quote__c q = queryQuote(quoteId);
        Map<String, Id> applied = new Map<String, Id>();

        if (q.SBQQ__Opportunity2__r == null || q.SBQQ__Opportunity2__r.Previous_Opportunity__c == null) {
            return applied;
        }

        SBQQ__Quote__c prevQuote = findPrimaryQuoteForOpportunity(q.SBQQ__Opportunity2__r.Previous_Opportunity__c);
        if (prevQuote == null) {
            return applied;
        }

        SBQQ__Quote__c prev = [
            SELECT SBQQ__PrimaryContact__c, Invoice_Contact__c, Creative_Contact__c, Event_Logistics_Contact__c, Signatory_Contact__c
            FROM SBQQ__Quote__c
            WHERE Id = :prevQuote.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Map<String, Id> currentValues = new Map<String, Id>{
            'primary' => q.SBQQ__PrimaryContact__c,
            'invoice' => q.Invoice_Contact__c,
            'creative' => q.Creative_Contact__c,
            'event' => q.Event_Logistics_Contact__c,
            'signatory' => q.Signatory_Contact__c
        };
        Map<String, Id> prevValues = new Map<String, Id>{
            'primary' => prev.SBQQ__PrimaryContact__c,
            'invoice' => prev.Invoice_Contact__c,
            'creative' => prev.Creative_Contact__c,
            'event' => prev.Event_Logistics_Contact__c,
            'signatory' => prev.Signatory_Contact__c
        };

        Map<String, Id> toApply = new Map<String, Id>();
        for (String role : FIELD_BY_ROLE.keySet()) {
            Id prevContactId = prevValues.get(role);
            if (prevContactId != null && currentValues.get(role) == null) {
                toApply.put(role, prevContactId);
            }
        }

        applyRoleWrites(q, toApply);
        applied.putAll(toApply);

        return applied;
    }

    /**
     * Scoped to the Quote's own Office account plus its Firm (Ultimate_Account__c)
     * and every other Office under that same Firm - not just the one Office the
     * Quote sits on. Same-office matches are returned first, then the rest of the
     * firm family, so a rep at a 200-office firm sees the relevant person without
     * wading through every sibling office.
     */
    @AuraEnabled(cacheable=true)
    public static List<ContactSearchResult> searchFamilyContacts(Id quoteId, String searchTerm) {
        SBQQ__Quote__c q = [
            SELECT SBQQ__Account__c, SBQQ__Account__r.Ultimate_Account__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Id officeId = q.SBQQ__Account__c;
        Id firmId = q.SBQQ__Account__r != null ? q.SBQQ__Account__r.Ultimate_Account__c : null;

        if (officeId == null) {
            return new List<ContactSearchResult>();
        }

        String likeTerm = '%' + (String.isBlank(searchTerm) ? '' : searchTerm.trim()) + '%';
        List<ContactSearchResult> results = new List<ContactSearchResult>();
        Set<Id> seenContactIds = new Set<Id>();

        for (Contact c : [
            SELECT Id, Name, Title, Account.Name
            FROM Contact
            WHERE AccountId = :officeId
            AND (Name LIKE :likeTerm OR Email LIKE :likeTerm)
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 10
        ]) {
            results.add(toSearchResult(c, true));
            seenContactIds.add(c.Id);
        }

        Set<Id> restOfFamily = new Set<Id>();
        if (firmId != null) {
            restOfFamily.add(firmId);
            for (Account sibling : [
                SELECT Id FROM Account WHERE Ultimate_Account__c = :firmId AND Id != :officeId WITH SECURITY_ENFORCED
            ]) {
                restOfFamily.add(sibling.Id);
            }
        }

        if (!restOfFamily.isEmpty()) {
            for (Contact c : [
                SELECT Id, Name, Title, Account.Name
                FROM Contact
                WHERE AccountId IN :restOfFamily
                AND (Name LIKE :likeTerm OR Email LIKE :likeTerm)
                AND Id NOT IN :seenContactIds
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
                LIMIT 40
            ]) {
                results.add(toSearchResult(c, false));
            }
        }

        return results;
    }

    private static ContactSearchResult toSearchResult(Contact c, Boolean sameOffice) {
        ContactSearchResult r = new ContactSearchResult();
        r.contactId = c.Id;
        r.name = c.Name;
        r.title = c.Title;
        r.accountName = c.Account != null ? c.Account.Name : null;
        r.sameOffice = sameOffice;
        return r;
    }

    // ---- internals ----

    private static SBQQ__Quote__c queryQuote(Id quoteId) {
        return [
            SELECT Id, SBQQ__Account__c, SBQQ__Account__r.Name, SBQQ__Type__c, ALM_Event_Product__c,
                   SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.Previous_Opportunity__c, SBQQ__Primary__c,
                   SBQQ__PrimaryContact__c, SBQQ__PrimaryContact__r.Name, SBQQ__PrimaryContact__r.Title,
                   Invoice_Contact__c, Invoice_Contact__r.Name, Invoice_Contact__r.Title,
                   Creative_Contact__c, Creative_Contact__r.Name, Creative_Contact__r.Title,
                   Event_Logistics_Contact__c, Event_Logistics_Contact__r.Name, Event_Logistics_Contact__r.Title,
                   Signatory_Contact__c, Signatory_Contact__r.Name, Signatory_Contact__r.Title
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    private static SBQQ__Quote__c queryQuoteForWrite(Id quoteId) {
        return [
            SELECT Id, SBQQ__Opportunity2__c, SBQQ__Primary__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    /**
     * Single write path shared by setRoleContact and copyFromPreviousQuote: the
     * Quote field(s), the Contact Role(s), and - for Invoice only, and only when
     * this Quote is the Opportunity's primary quote - the Opportunity field.
     *
     * Batched by design: copyFromPreviousQuote can carry forward up to 4 roles in
     * one rep action, and each role used to run its own separate Quote update and
     * OpportunityContactRole query/DML. That meant one click could fire the Quote's
     * save automation (CPQ calc, etc.) up to 4 times in a single transaction - in an
     * org whose legacy Opportunity-save flows have already tripped the 100-SOQL
     * limit twice. Collapsing every role into one Quote update and one OCR
     * query/DML pass keeps a multi-role copy the same automation cost as a
     * single-role edit.
     */
    private static void applyRoleWrite(SBQQ__Quote__c q, String role, Id contactId) {
        applyRoleWrites(q, new Map<String, Id>{ role => contactId });
    }

    private static void applyRoleWrites(SBQQ__Quote__c q, Map<String, Id> roleToContactId) {
        if (roleToContactId.isEmpty()) {
            return;
        }

        updateQuoteFields(q.Id, roleToContactId);

        if (q.SBQQ__Opportunity2__c != null) {
            syncContactRoles(q.SBQQ__Opportunity2__c, roleToContactId);
        }

        Id invoiceContactId = roleToContactId.get('invoice');
        if (invoiceContactId != null && q.SBQQ__Opportunity2__c != null && q.SBQQ__Primary__c == true) {
            syncInvoiceContactToOpportunity(q.SBQQ__Opportunity2__c, invoiceContactId);
        }
    }

    private static void syncInvoiceContactToOpportunity(Id opportunityId, Id contactId) {
        Opportunity toUpdate = new Opportunity(Id = opportunityId, Invoice_Contact__c = contactId);
        List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ toUpdate }).getRecords();
        update stripped;
    }

    private static ContactRoleInfo buildRoleInfo(Id contactId, Contact c, Map<String, Id> ocrContactByRole, String roleKey) {
        ContactRoleInfo info = new ContactRoleInfo();
        info.contactId = contactId;
        if (c != null) {
            info.name = c.Name;
            info.title = c.Title;
        }
        if (contactId != null) {
            Id ocrContactId = ocrContactByRole.get(OCR_ROLE_BY_KEY.get(roleKey));
            info.source = (ocrContactId == contactId) ? 'synced' : 'manual';
        }
        return info;
    }

    private static Map<String, Id> ocrContactsByRole(Id opportunityId) {
        Map<String, Id> result = new Map<String, Id>();
        if (opportunityId == null) {
            return result;
        }
        for (OpportunityContactRole ocr : [
            SELECT ContactId, Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
            AND Role IN :OCR_ROLE_BY_KEY.values()
            WITH SECURITY_ENFORCED
        ]) {
            result.put(ocr.Role, ocr.ContactId);
        }
        return result;
    }

    private static SBQQ__Quote__c findPrimaryQuoteForOpportunity(Id opportunityId) {
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, Name
            FROM SBQQ__Quote__c
            WHERE SBQQ__Opportunity2__c = :opportunityId
            WITH SECURITY_ENFORCED
            ORDER BY SBQQ__Primary__c DESC, LastModifiedDate DESC
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0];
    }

    private static void updateQuoteFields(Id quoteId, Map<String, Id> roleToContactId) {
        SBQQ__Quote__c toUpdate = new SBQQ__Quote__c(Id = quoteId);
        for (String role : roleToContactId.keySet()) {
            toUpdate.put(FIELD_BY_ROLE.get(role), roleToContactId.get(role));
        }
        List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ toUpdate }).getRecords();
        update stripped;
    }

    private static void syncContactRoles(Id opportunityId, Map<String, Id> roleToContactId) {
        Map<String, Id> contactByTargetRole = new Map<String, Id>();
        for (String role : roleToContactId.keySet()) {
            Id contactId = roleToContactId.get(role);
            if (contactId != null) {
                contactByTargetRole.put(OCR_ROLE_BY_KEY.get(role), contactId);
            }
        }
        if (contactByTargetRole.isEmpty()) {
            return;
        }

        Map<String, OpportunityContactRole> existingByTargetRole = new Map<String, OpportunityContactRole>();
        for (OpportunityContactRole ocr : [
            SELECT Id, ContactId, Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
            AND Role IN :contactByTargetRole.keySet()
            WITH SECURITY_ENFORCED
        ]) {
            existingByTargetRole.put(ocr.Role, ocr);
        }

        List<OpportunityContactRole> toUpdate = new List<OpportunityContactRole>();
        List<OpportunityContactRole> toInsert = new List<OpportunityContactRole>();

        for (String targetRole : contactByTargetRole.keySet()) {
            Id contactId = contactByTargetRole.get(targetRole);
            OpportunityContactRole existing = existingByTargetRole.get(targetRole);
            if (existing != null) {
                if (existing.ContactId != contactId) {
                    toUpdate.add(new OpportunityContactRole(Id = existing.Id, ContactId = contactId));
                }
            } else {
                toInsert.add(new OpportunityContactRole(
                    OpportunityId = opportunityId,
                    ContactId = contactId,
                    Role = targetRole,
                    IsPrimary = (targetRole == OCR_ROLE_BY_KEY.get('primary'))
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate).getRecords();
            update stripped;
        }
        if (!toInsert.isEmpty()) {
            List<SObject> stripped = Security.stripInaccessible(AccessType.CREATABLE, toInsert).getRecords();
            insert stripped;
        }
    }
}
