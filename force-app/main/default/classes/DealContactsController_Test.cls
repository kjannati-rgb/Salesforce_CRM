@isTest
private class DealContactsController_Test {

    // Opportunity.flow-meta.xml ("Opportunity_AfterUpdate_MasterFlow") is the legacy,
    // Process-Builder-migrated after-save flow on Opportunity - it is heavy enough
    // (SOQL-wise) that two full Opportunity saves in one test transaction trip the
    // 100-query limit. Bypass it for this test class only; leave the modern autolaunched
    // flows (Check_Completeness_of_Contact_Roles, Opportunity_Contact_Role_Create) alone,
    // since those are exactly the org behavior these tests rely on being real.
    @TestSetup
    static void setup() {
        insert new Application_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Disable_Process_Builders__c = true
        );
    }

    // Billing address set unconditionally so any Opportunity on this Account can satisfy
    // Check_Completeness_of_Contact_Roles' Require_Account_Billing_Address__c check.
    private static Id firmRecordTypeId;

    private static Id getFirmRecordTypeId() {
        if (firmRecordTypeId == null) {
            firmRecordTypeId = [
                SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Firm' LIMIT 1
            ].Id;
        }
        return firmRecordTypeId;
    }

    private static Account makeAccount(String name) {
        // Ultimate_Account__c (the Firm) must be a distinct record from the Office
        // Account itself, on the Firm record type - a self-reference trips the hierarchy
        // circular-dependency check, and a non-Firm record type is rejected outright.
        Account firm = new Account(Name = name + ' (Firm)', RecordTypeId = getFirmRecordTypeId());
        insert firm;

        Account acc = new Account(
            Name = name,
            BillingStreet = '1 Fleet Street',
            BillingCity = 'London',
            BillingCountry = 'United Kingdom',
            Ultimate_Account__c = firm.Id
        );
        insert acc;
        return acc;
    }

    // A second Office under the same Firm as an existing Office - for family-search tests.
    private static Account makeSiblingOffice(String name, Id firmId) {
        Account acc = new Account(
            Name = name,
            BillingStreet = '1 Fleet Street',
            BillingCity = 'London',
            BillingCountry = 'United Kingdom',
            Ultimate_Account__c = firmId
        );
        insert acc;
        return acc;
    }

    // Email/Title/Mailing fields set unconditionally so any Contact used as a primary
    // Contact Role satisfies Check_Completeness_of_Contact_Roles' required-field checks.
    private static Contact makeContact(String firstName, String lastName, Id accountId) {
        Contact c = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId,
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + '@farrowsinclair.example',
            Title = 'Contact',
            MailingStreet = '1 Fleet Street',
            MailingCity = 'London'
        );
        insert c;
        return c;
    }

    private static Opportunity makeOpportunity(String name, Id accountId, Id previousOpportunityId) {
        return makeOpportunity(name, accountId, previousOpportunityId, 'Identify');
    }

    private static Opportunity makeOpportunity(String name, Id accountId, Id previousOpportunityId, String stageName) {
        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = stageName,
            CloseDate = Date.today().addMonths(1),
            Previous_Opportunity__c = previousOpportunityId
        );
        insert opp;
        return opp;
    }

    // Check_Completeness_of_Contact_Roles blocks a Closed Won save without a complete
    // primary Contact Role - so give the Opportunity one before flipping its stage.
    private static void closeOpportunityAsWon(Opportunity opp, Id primaryContactId) {
        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = primaryContactId,
            Role = 'Decision Maker',
            IsPrimary = true
        );
        opp.StageName = 'Closed Won';
        update opp;
    }

    // ALM_Event_Product__c is calculated from Quote Line Items and is not directly
    // writeable - hasAlmEvent is a pass-through read in the controller, not exercised
    // here at the field level.
    private static SBQQ__Quote__c makeQuote(Id opportunityId, Id accountId, String type) {
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opportunityId,
            SBQQ__Account__c = accountId,
            SBQQ__Type__c = type
        );
        insert q;
        return q;
    }

    @isTest
    static void getPanelData_returnsEmptyRolesForFreshQuote() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');

        Test.startTest();
        DealContactsController.PanelData data = DealContactsController.getPanelData(quote.Id);
        Test.stopTest();

        System.assertEquals(acc.Id, data.accountId, 'accountId should come from the Quote');
        System.assertEquals(false, data.isRenewal, 'Type=Quote is not a Renewal');
        System.assertEquals(false, data.hasAlmEvent, 'no ALM Event amount set');
        System.assertEquals(null, data.roles.get('primary').contactId, 'primary should start unset');
        System.assertEquals(null, data.roles.get('invoice').contactId, 'invoice should start unset');
        System.assertEquals(null, data.previousQuoteId, 'no previous opportunity linked');
    }

    @isTest
    static void setRoleContact_updatesQuoteFieldAndCreatesContactRole() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact primaryContact = makeContact('Elena', 'Whitfield', acc.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');

        Test.startTest();
        DealContactsController.setRoleContact(quote.Id, 'primary', primaryContact.Id, 'manual');
        Test.stopTest();

        SBQQ__Quote__c updated = [SELECT SBQQ__PrimaryContact__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals(primaryContact.Id, updated.SBQQ__PrimaryContact__c, 'Quote field should be written');

        List<OpportunityContactRole> ocrs = [
            SELECT ContactId, Role, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :opp.Id
        ];
        System.assertEquals(1, ocrs.size(), 'exactly one Contact Role should be created');
        System.assertEquals('Decision Maker', ocrs[0].Role, 'primary maps to Decision Maker');
        System.assertEquals(true, ocrs[0].IsPrimary, 'primary role should be flagged IsPrimary');
        System.assertEquals(primaryContact.Id, ocrs[0].ContactId);
    }

    @isTest
    static void setRoleContact_forInvoiceUsesInvoiceRecipientRoleAndIsNotPrimary() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact invoiceContact = makeContact('Tobias', 'Reyes', acc.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');

        Test.startTest();
        DealContactsController.setRoleContact(quote.Id, 'invoice', invoiceContact.Id, 'manual');
        Test.stopTest();

        List<OpportunityContactRole> ocrs = [
            SELECT ContactId, Role, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :opp.Id
        ];
        System.assertEquals(1, ocrs.size());
        System.assertEquals('Invoice Recipient', ocrs[0].Role);
        System.assertEquals(false, ocrs[0].IsPrimary, 'invoice role is never the primary decision maker flag');
    }

    @isTest
    static void setRoleContact_secondCallUpdatesExistingContactRoleInsteadOfDuplicating() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact first = makeContact('Priya', 'Anand', acc.Id);
        Contact second = makeContact('Marcus', 'Doyle', acc.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');

        Test.startTest();
        DealContactsController.setRoleContact(quote.Id, 'event', first.Id, 'manual');
        DealContactsController.setRoleContact(quote.Id, 'event', second.Id, 'manual');
        Test.stopTest();

        List<OpportunityContactRole> ocrs = [
            SELECT ContactId, Role FROM OpportunityContactRole
            WHERE OpportunityId = :opp.Id AND Role = 'Event Logistical Contact'
        ];
        System.assertEquals(1, ocrs.size(), 'changing the contact should update the same role row, not add a second one');
        System.assertEquals(second.Id, ocrs[0].ContactId);
    }

    @isTest
    static void copyFromPreviousQuote_carriesOnlyWhatWasSetAndLeavesGapsBlank() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact primaryContact = makeContact('Elena', 'Whitfield', acc.Id);
        Contact invoiceContact = makeContact('Tobias', 'Reyes', acc.Id);

        Opportunity previousOpp = makeOpportunity('Global Research Platform (prior term)', acc.Id, null);
        closeOpportunityAsWon(previousOpp, primaryContact.Id);
        SBQQ__Quote__c previousQuote = makeQuote(previousOpp.Id, acc.Id, 'Quote');
        previousQuote.SBQQ__PrimaryContact__c = primaryContact.Id;
        previousQuote.Invoice_Contact__c = invoiceContact.Id;
        // Creative_Contact__c and Event_Logistics_Contact__c intentionally left blank,
        // matching the real gap: those two were never captured on the original quote.
        update previousQuote;

        Opportunity renewalOpp = makeOpportunity('Global Research Platform', acc.Id, previousOpp.Id);
        SBQQ__Quote__c renewalQuote = makeQuote(renewalOpp.Id, acc.Id, 'Renewal');

        Test.startTest();
        DealContactsController.PanelData before = DealContactsController.getPanelData(renewalQuote.Id);
        System.assertEquals(previousQuote.Id, before.previousQuoteId, 'should resolve the prior quote via Previous_Opportunity__c');

        Map<String, Id> applied = DealContactsController.copyFromPreviousQuote(renewalQuote.Id);
        Test.stopTest();

        System.assertEquals(2, applied.size(), 'only primary and invoice were set on the previous quote');
        System.assertEquals(primaryContact.Id, applied.get('primary'));
        System.assertEquals(invoiceContact.Id, applied.get('invoice'));

        SBQQ__Quote__c updatedRenewal = [
            SELECT SBQQ__PrimaryContact__c, Invoice_Contact__c, Creative_Contact__c, Event_Logistics_Contact__c
            FROM SBQQ__Quote__c WHERE Id = :renewalQuote.Id
        ];
        System.assertEquals(primaryContact.Id, updatedRenewal.SBQQ__PrimaryContact__c);
        System.assertEquals(invoiceContact.Id, updatedRenewal.Invoice_Contact__c);
        System.assertEquals(null, updatedRenewal.Creative_Contact__c, 'Creative was never on the previous quote either - stays blank, not invented');
        System.assertEquals(null, updatedRenewal.Event_Logistics_Contact__c);

        List<OpportunityContactRole> ocrs = [
            SELECT Role FROM OpportunityContactRole WHERE OpportunityId = :renewalOpp.Id
        ];
        System.assertEquals(2, ocrs.size(), 'copying from renewal should also sync Contact Role for each carried field');
    }

    @isTest
    static void copyFromPreviousQuote_doesNotOverwriteAlreadySetFields() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact previousPrimary = makeContact('Elena', 'Whitfield', acc.Id);
        Contact currentPrimary = makeContact('Marcus', 'Doyle', acc.Id);

        Opportunity previousOpp = makeOpportunity('Global Research Platform (prior term)', acc.Id, null);
        closeOpportunityAsWon(previousOpp, previousPrimary.Id);
        SBQQ__Quote__c previousQuote = makeQuote(previousOpp.Id, acc.Id, 'Quote');
        previousQuote.SBQQ__PrimaryContact__c = previousPrimary.Id;
        update previousQuote;

        Opportunity renewalOpp = makeOpportunity('Global Research Platform', acc.Id, previousOpp.Id);
        SBQQ__Quote__c renewalQuote = makeQuote(renewalOpp.Id, acc.Id, 'Renewal');
        renewalQuote.SBQQ__PrimaryContact__c = currentPrimary.Id;
        update renewalQuote;

        Test.startTest();
        Map<String, Id> applied = DealContactsController.copyFromPreviousQuote(renewalQuote.Id);
        Test.stopTest();

        System.assertEquals(false, applied.containsKey('primary'), 'primary was already set - copy should skip it');

        SBQQ__Quote__c reQueried = [SELECT SBQQ__PrimaryContact__c FROM SBQQ__Quote__c WHERE Id = :renewalQuote.Id];
        System.assertEquals(currentPrimary.Id, reQueried.SBQQ__PrimaryContact__c, 'existing value must not be clobbered');
    }

    @isTest
    static void getPanelData_reportsManualSourceWhenFieldWasSetWithoutGoingThroughController() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact contact = makeContact('Priya', 'Anand', acc.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');
        quote.Creative_Contact__c = contact.Id;
        update quote;

        Test.startTest();
        DealContactsController.PanelData data = DealContactsController.getPanelData(quote.Id);
        Test.stopTest();

        System.assertEquals(contact.Id, data.roles.get('creative').contactId);
        System.assertEquals('manual', data.roles.get('creative').source, 'no matching Contact Role exists, so this reads as manual, not synced');
    }

    @isTest
    static void setRoleContact_rejectsUnknownRoleKey() {
        Account acc = makeAccount('Farrow & Sinclair LLP');
        Contact contact = makeContact('Priya', 'Anand', acc.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', acc.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, acc.Id, 'Quote');

        Test.startTest();
        Boolean threw = false;
        try {
            DealContactsController.setRoleContact(quote.Id, 'ship_to', contact.Id, 'manual');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'an unrecognised role key should be rejected, not silently ignored');
    }

    @isTest
    static void searchFamilyContacts_prioritizesSameOfficeOverRestOfFirm() {
        Account office = makeAccount('Farrow & Sinclair LLP');
        Account sibling = makeSiblingOffice('Farrow & Sinclair LLP - New York', office.Ultimate_Account__c);
        Contact sameOfficeMatch = makeContact('Aiden', 'Foster', office.Id);
        Contact siblingOfficeMatch = makeContact('Amara', 'Foster', sibling.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', office.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, office.Id, 'Quote');

        Test.startTest();
        List<DealContactsController.ContactSearchResult> results = DealContactsController.searchFamilyContacts(quote.Id, 'Foster');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'should find the match at this office and the match at the sibling office');
        System.assertEquals(sameOfficeMatch.Id, results[0].contactId, 'same-office match must come first');
        System.assertEquals(true, results[0].sameOffice);
        System.assertEquals(siblingOfficeMatch.Id, results[1].contactId, 'sibling-office match still included, just after');
        System.assertEquals(false, results[1].sameOffice);
        System.assertEquals(sibling.Name, results[1].accountName, 'result should surface which office the contact sits at');
    }

    @isTest
    static void searchFamilyContacts_excludesContactsAtUnrelatedFirms() {
        Account office = makeAccount('Farrow & Sinclair LLP');
        Opportunity opp = makeOpportunity('Global Research Platform', office.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, office.Id, 'Quote');

        Account unrelatedOffice = makeAccount('Meridian & Cole LLP');
        makeContact('Rosa', 'Foster', unrelatedOffice.Id);

        Test.startTest();
        List<DealContactsController.ContactSearchResult> results = DealContactsController.searchFamilyContacts(quote.Id, 'Foster');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'a same-named contact at a completely different firm must not appear');
    }

    @isTest
    static void searchFamilyContacts_blankTermReturnsWholeFamily() {
        Account office = makeAccount('Farrow & Sinclair LLP');
        Account sibling = makeSiblingOffice('Farrow & Sinclair LLP - New York', office.Ultimate_Account__c);
        makeContact('Elena', 'Whitfield', office.Id);
        makeContact('Wes', 'Okafor', sibling.Id);
        Opportunity opp = makeOpportunity('Global Research Platform', office.Id, null);
        SBQQ__Quote__c quote = makeQuote(opp.Id, office.Id, 'Quote');

        Test.startTest();
        List<DealContactsController.ContactSearchResult> results = DealContactsController.searchFamilyContacts(quote.Id, '');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'a blank search term should default to the whole firm family, same-office first');
    }
}
