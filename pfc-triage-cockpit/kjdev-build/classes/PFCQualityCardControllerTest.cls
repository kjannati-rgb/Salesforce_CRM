@IsTest
private class PFCQualityCardControllerTest {

    private static final String FREEMAIL = 'prospect.tester@gmail.com';
    private static final String CORPORATE = 'prospect.tester@bigfirm-test.example';

    @TestSetup
    static void makeData() {
        // Org automation (incl. "Subscription Process - Edit" PB, which breaks on
        // contract-less test subscriptions) honours the Application_Settings__c kill
        // switches — reuse the FSS helper that flips them for the running user.
        FirmRollupTestData.bypassOrgAutomation();
        // Ultimate_Account__c carries a lookup filter: target must be Record Type "Firm".
        Account firm = new Account(Name = 'QC Test Firm LLP');
        Schema.RecordTypeInfo firmRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Firm');
        if (firmRt != null) {
            firm.RecordTypeId = firmRt.getRecordTypeId();
        }
        insert firm;
        Account office = new Account(Name = 'QC Test Firm LLP (Paris)', Ultimate_Account__c = firm.Id);
        insert office;
        Contact con = new Contact(FirstName = 'Quinn', LastName = 'CardTest', AccountId = office.Id, Email = CORPORATE);
        insert con;
        Lead led = new Lead(FirstName = 'Quincy', LastName = 'CardLead', Company = 'Solo Co', Email = FREEMAIL);
        insert led;

        // Reporting_Stream__c is org-required AND a restricted picklist dependent on
        // Division__c — inserts reject (division, stream) pairs the dependency doesn't
        // allow, so resolve a valid pair from the validFor bitmap.
        Product2 pSpec = new Product2(Name = 'QC Spec Product', Family = 'Subs - Specialist Platforms', IsActive = true);
        Product2 pPro = new Product2(Name = 'QC Pro Product', Family = 'Subs - Lexology Pro', IsActive = true);
        setValidDivisionAndStream(pSpec);
        setValidDivisionAndStream(pPro);
        insert new List<Product2>{ pSpec, pPro };

        // SBQQ__StartDate__c / SBQQ__EndDate__c are formulas over the writable
        // SBQQ__SubscriptionStartDate__c / SBQQ__SubscriptionEndDate__c (see FirmRollupTestData).
        List<SBQQ__Subscription__c> subs = new List<SBQQ__Subscription__c>();
        for (Integer i = 0; i < 3; i++) {
            subs.add(new SBQQ__Subscription__c(
                Ultimate_Parent__c = firm.Id, SBQQ__Account__c = office.Id, SBQQ__Product__c = pSpec.Id,
                SBQQ__SubscriptionStartDate__c = Date.today().addDays(-30),
                SBQQ__SubscriptionEndDate__c = Date.today().addDays(300),
                SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 1000, CurrencyIsoCode = 'GBP'));
        }
        subs.add(new SBQQ__Subscription__c(
            Ultimate_Parent__c = firm.Id, SBQQ__Account__c = office.Id, SBQQ__Product__c = pPro.Id,
            SBQQ__SubscriptionStartDate__c = Date.today().addDays(-30),
            SBQQ__SubscriptionEndDate__c = Date.today().addDays(300),
            SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 500, CurrencyIsoCode = 'GBP'));
        // Expired — must be excluded from the rollup.
        subs.add(new SBQQ__Subscription__c(
            Ultimate_Parent__c = firm.Id, SBQQ__Account__c = office.Id, SBQQ__Product__c = pSpec.Id,
            SBQQ__SubscriptionStartDate__c = Date.today().addDays(-400),
            SBQQ__SubscriptionEndDate__c = Date.today().addDays(-35),
            SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 1000, CurrencyIsoCode = 'GBP'));
        insert subs;
    }

    private static void setValidDivisionAndStream(Product2 p) {
        List<Schema.PicklistEntry> divisions = Product2.Division__c.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry stream : Product2.Reporting_Stream__c.getDescribe().getPicklistValues()) {
            if (!stream.isActive()) {
                continue;
            }
            String validFor = (String) ((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(stream))).get('validFor');
            if (String.isBlank(validFor)) {
                continue;
            }
            for (Integer i = 0; i < divisions.size(); i++) {
                if (divisions[i].isActive() && isBitSet(validFor, i)) {
                    p.Division__c = divisions[i].getValue();
                    p.Reporting_Stream__c = stream.getValue();
                    return;
                }
            }
        }
        throw new IllegalArgumentException('No valid Division/Reporting Stream pair found on Product2');
    }

    private static Boolean isBitSet(String validFor, Integer index) {
        String b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        Integer charIdx = index / 6;
        if (charIdx >= validFor.length()) {
            return false;
        }
        Integer sextet = b64.indexOf(validFor.substring(charIdx, charIdx + 1));
        Integer bit = 5 - Math.mod(index, 6);
        return sextet >= 0 && (sextet & (1 << bit)) != 0;
    }

    private static Pardot_Form_Completion__c makePfc(Id leadId, Id contactId, String brand) {
        Pardot_Form_Completion__c pfc = new Pardot_Form_Completion__c(
            Name = 'QC Test', Sales_Stage__c = 'New',
            Lead__c = leadId, Contact__c = contactId, Product_Brand__c = brand);
        insert pfc;
        return pfc;
    }

    @IsTest
    static void leadModeFreemailAndPendingScore() {
        Lead led = [SELECT Id FROM Lead LIMIT 1];
        Pardot_Form_Completion__c pfc = makePfc(led.Id, null, 'Lexology');

        Test.startTest();
        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);
        Test.stopTest();

        System.assertEquals('lead', data.mode);
        System.assertEquals(null, data.fitScore, 'no score has landed — must be null, never faked');
        System.assertEquals('freemail', data.domainClass);
        System.assertEquals('gmail.com', data.domainName);
        System.assertEquals(null, data.firm, 'lead mode carries no firm context');
    }

    @IsTest
    static void contactModeRollupAndOverlap() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Pardot_Form_Completion__c pfc = makePfc(null, con.Id, 'IAM');
        pfc.Fit_Score__c = 87;
        update pfc;

        Test.startTest();
        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);
        Test.stopTest();

        System.assertEquals('contact', data.mode);
        System.assertEquals('corporate', data.domainClass);
        System.assertNotEquals(null, data.firm);
        System.assertEquals(4, data.firm.activeSubs, 'expired subscription must be excluded');
        System.assertEquals(2, data.firm.familyCount);
        System.assert(data.firm.existingCustomer);
        System.assertEquals('QC Test Firm LLP', data.firm.firmName, 'rollup must resolve to the ultimate account');
        System.assertEquals('QC Test Firm LLP (Paris)', data.firm.officeName);
        System.assert(data.firm.requestedBrandFamilyOverlap,
            'IAM maps to Subs - Specialist Platforms which the firm holds');
    }

    @IsTest
    static void contactModeNoOverlapForUnmappedBrand() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Pardot_Form_Completion__c pfc = makePfc(null, con.Id, 'Other');

        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);

        System.assertEquals(null, data.firm.requestedFamily, '"Other" is deliberately unmapped');
        System.assert(!data.firm.requestedBrandFamilyOverlap);
    }

    @IsTest
    static void duplicatesFoundAcrossLeadAndContactWithSameEmail() {
        Lead led = [SELECT Id FROM Lead LIMIT 1];
        // second lead, same email — sibling PFC should be found via email match
        Lead led2 = new Lead(FirstName = 'Dup', LastName = 'CardLead2', Company = 'Solo Co', Email = FREEMAIL);
        insert led2;
        Pardot_Form_Completion__c sibling = makePfc(led2.Id, null, 'Lexology');
        Pardot_Form_Completion__c pfc = makePfc(led.Id, null, 'Lexology');

        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);

        System.assertEquals(1, data.duplicates.size(), 'sibling PFC via same-email lead must surface');
        System.assertEquals(sibling.Id, data.duplicates[0].recordId);
    }

    // NOTE: a truly account-less contact cannot be inserted in this org (VR "Please add the
    // Account to the Contact record", not bypass-aware) — the null-firm render path is
    // covered by the LWC Jest suite instead.
    @IsTest
    static void contactModeFallsBackToContactsAccountWhenStampMissing() {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'CardTest' AND AccountId != null LIMIT 1];
        // Simulate a record created already-closed: PFC_On_Save never stamped Account_Contact__c.
        Pardot_Form_Completion__c pfc = new Pardot_Form_Completion__c(
            Name = 'QC Closed At Birth', Sales_Stage__c = 'Converted',
            Contact__c = con.Id, Product_Brand__c = 'IAM');
        insert pfc;
        System.assertEquals(null, [SELECT Account_Contact__c FROM Pardot_Form_Completion__c WHERE Id = :pfc.Id].Account_Contact__c,
            'test premise: closed-at-birth record has no account stamp');

        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);

        System.assertNotEquals(null, data.firm, 'must fall back to the contact\'s own account');
        System.assertEquals('QC Test Firm LLP', data.firm.firmName);
        System.assertEquals(4, data.firm.activeSubs);
    }

    @IsTest
    static void orphanRecordNoEmailNoDuplicatesNoCrash() {
        Pardot_Form_Completion__c pfc = makePfc(null, null, null);

        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);

        System.assertEquals('lead', data.mode, 'no contact -> lead mode');
        System.assertEquals('none', data.domainClass);
        System.assertEquals(0, data.duplicates.size());
        System.assertEquals(null, data.firm);
    }

    @IsTest
    static void registrableDomainParsing() {
        System.assertEquals('sub.firm.co.uk', PFCQualityCardController.registrableDomain('A.B@Sub.Firm.CO.UK '));
        System.assertEquals(null, PFCQualityCardController.registrableDomain('not-an-email'));
        System.assertEquals(null, PFCQualityCardController.registrableDomain(null));
    }

    @IsTest
    static void bulkSiblings() {
        Lead led = [SELECT Id FROM Lead LIMIT 1];
        List<Pardot_Form_Completion__c> many = new List<Pardot_Form_Completion__c>();
        for (Integer i = 0; i < 15; i++) {
            many.add(new Pardot_Form_Completion__c(Name = 'Bulk ' + i, Sales_Stage__c = 'New', Lead__c = led.Id));
        }
        insert many;
        Pardot_Form_Completion__c pfc = makePfc(led.Id, null, 'Lexology');

        PFCQualityCardController.CardData data = PFCQualityCardController.getCardData(pfc.Id);

        System.assertEquals(10, data.duplicates.size(), 'duplicate list is capped at 10');
    }
}
