/**
 * Backs the dealContacts LWC. Reads/writes the four Quote-level contact
 * roles (Primary, Invoice, Creative, Event Logistics) and keeps a matching
 * OpportunityContactRole in sync using this org's existing Role picklist
 * values (Decision Maker / Invoice Recipient / Creative Contact /
 * Event Logistical Contact) - no new fields required.
 */
public with sharing class DealContactsController {

    private static final Map<String, String> FIELD_BY_ROLE = new Map<String, String>{
        'primary' => 'SBQQ__PrimaryContact__c',
        'invoice' => 'Invoice_Contact__c',
        'creative' => 'Creative_Contact__c',
        'event' => 'Event_Logistics_Contact__c'
    };

    private static final Map<String, String> OCR_ROLE_BY_KEY = new Map<String, String>{
        'primary' => 'Decision Maker',
        'invoice' => 'Invoice Recipient',
        'creative' => 'Creative Contact',
        'event' => 'Event Logistical Contact'
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
            'event' => buildRoleInfo(q.Event_Logistics_Contact__c, q.Event_Logistics_Contact__r, ocrContactByRole, 'event')
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
        updateQuoteField(q.Id, role, contactId);
        if (q.SBQQ__Opportunity2__c != null) {
            syncContactRole(q.SBQQ__Opportunity2__c, role, contactId);
        }
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
            SELECT SBQQ__PrimaryContact__c, Invoice_Contact__c, Creative_Contact__c, Event_Logistics_Contact__c
            FROM SBQQ__Quote__c
            WHERE Id = :prevQuote.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Map<String, Id> currentValues = new Map<String, Id>{
            'primary' => q.SBQQ__PrimaryContact__c,
            'invoice' => q.Invoice_Contact__c,
            'creative' => q.Creative_Contact__c,
            'event' => q.Event_Logistics_Contact__c
        };
        Map<String, Id> prevValues = new Map<String, Id>{
            'primary' => prev.SBQQ__PrimaryContact__c,
            'invoice' => prev.Invoice_Contact__c,
            'creative' => prev.Creative_Contact__c,
            'event' => prev.Event_Logistics_Contact__c
        };

        for (String role : FIELD_BY_ROLE.keySet()) {
            Id prevContactId = prevValues.get(role);
            if (prevContactId != null && currentValues.get(role) == null) {
                updateQuoteField(q.Id, role, prevContactId);
                if (q.SBQQ__Opportunity2__c != null) {
                    syncContactRole(q.SBQQ__Opportunity2__c, role, prevContactId);
                }
                applied.put(role, prevContactId);
            }
        }

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
                   SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.Previous_Opportunity__c,
                   SBQQ__PrimaryContact__c, SBQQ__PrimaryContact__r.Name, SBQQ__PrimaryContact__r.Title,
                   Invoice_Contact__c, Invoice_Contact__r.Name, Invoice_Contact__r.Title,
                   Creative_Contact__c, Creative_Contact__r.Name, Creative_Contact__r.Title,
                   Event_Logistics_Contact__c, Event_Logistics_Contact__r.Name, Event_Logistics_Contact__r.Title
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    private static SBQQ__Quote__c queryQuoteForWrite(Id quoteId) {
        return [
            SELECT Id, SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
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
            AND Role IN ('Decision Maker', 'Invoice Recipient', 'Creative Contact', 'Event Logistical Contact')
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

    private static void updateQuoteField(Id quoteId, String role, Id contactId) {
        SBQQ__Quote__c toUpdate = new SBQQ__Quote__c(Id = quoteId);
        toUpdate.put(FIELD_BY_ROLE.get(role), contactId);
        List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ toUpdate }).getRecords();
        update stripped;
    }

    private static void syncContactRole(Id opportunityId, String role, Id contactId) {
        if (contactId == null) {
            return;
        }
        String targetRole = OCR_ROLE_BY_KEY.get(role);
        List<OpportunityContactRole> existing = [
            SELECT Id, ContactId
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
            AND Role = :targetRole
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            if (existing[0].ContactId != contactId) {
                OpportunityContactRole toUpdate = new OpportunityContactRole(Id = existing[0].Id, ContactId = contactId);
                List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ toUpdate }).getRecords();
                update stripped;
            }
            return;
        }

        OpportunityContactRole toInsert = new OpportunityContactRole(
            OpportunityId = opportunityId,
            ContactId = contactId,
            Role = targetRole,
            IsPrimary = (role == 'primary')
        );
        List<SObject> stripped = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ toInsert }).getRecords();
        insert stripped;
    }
}
