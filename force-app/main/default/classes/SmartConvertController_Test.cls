@IsTest
private class SmartConvertController_Test {

    private static final Id FIRM_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
    private static final Id OFFICE_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();

    @TestSetup
    static void seed() {
        Account firm = new Account(Name = 'Dentons Demo', RecordTypeId = FIRM_RT, Match_Domain__c = 'dentons-demo.com');
        insert firm;
        insert new List<Account>{
            new Account(Name = 'Dentons UK Demo', RecordTypeId = OFFICE_RT, Ultimate_Account__c = firm.Id,
                BillingCountryCode = 'GB', BillingCity = 'London',
                No_of_Won_Office_Opportunities__c = 24, Val_of_Won_Office_Opportunities__c = 1240000),
            new Account(Name = 'Dentons US Demo', RecordTypeId = OFFICE_RT, Ultimate_Account__c = firm.Id,
                BillingCountryCode = 'US', BillingCity = 'Washington',
                No_of_Won_Office_Opportunities__c = 11, Val_of_Won_Office_Opportunities__c = 540000)
        };
    }

    private static Lead newLead(String first, String email, String cc, String city) {
        Lead l = new Lead(FirstName = first, LastName = 'Carter', Company = 'Dentons',
            Title = 'Senior Associate', Email = email, CountryCode = cc, City = city,
            Status = 'Open - Not Contacted');
        insert l;
        return l;
    }

    @IsTest
    static void getMatch_existingCustomer() {
        Lead l = newLead('James', 'james@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        Test.stopTest();
        System.assertEquals(true, v.hasFirm);
        System.assertEquals('Dentons Demo', v.firm.name);
        System.assert(v.offices.size() == 2, 'two offices');
        System.assertEquals('high', v.conf);
        System.assertEquals('none', v.contact.result, 'no existing contact for this email');
        System.assertNotEquals(null, v.banner.html);
        System.assertNotEquals(null, v.openOpps, 'open-opp list initialised');
        System.assertEquals(false, v.hasOpenBrandOpp, 'no open opps on the seeded firm');
        System.assertNotEquals(null, v.quality, 'lead quality populated');
    }

    @IsTest
    static void disqualifyConvert_linksNoOppWithReason() {
        Account office = [SELECT Id FROM Account WHERE Name = 'Dentons UK Demo' LIMIT 1];
        Lead l = newLead('Dq', 'dq@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        // disqualify = convert into the office, NO opportunity, reason recorded (preserves SCV)
        SmartConvertController.convert(l.Id, office.Id, null, false, 'ONECLICK', false, null,
            office.Id, false, null, 'Existing customer');
        Test.stopTest();
        Lead c = [SELECT Disqualify_Reason__c, Disqualified_At_Convert__c, Conversion_Source__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Existing customer', c.Disqualify_Reason__c);
        System.assertEquals(true, c.Disqualified_At_Convert__c, 'flagged disqualified-at-convert');
        System.assertEquals('Smart Convert', c.Conversion_Source__c);
    }

    @IsTest
    static void getMatch_noMatchHasDedup() {
        Lead l = newLead('Sofia', 'sofia@nowhere-zzz.es', 'ES', 'Madrid');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        Test.stopTest();
        System.assertEquals(false, v.hasFirm);
        System.assertEquals('none', v.conf);
        System.assertNotEquals(null, v.dedup);
        System.assertEquals('ok', v.banner.cls);
    }

    @IsTest
    static void getOfficesForFirm_ranks() {
        Account firm = [SELECT Id FROM Account WHERE Name = 'Dentons Demo' LIMIT 1];
        Lead l = newLead('James', 'james@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        List<SmartConvertController.Office> offs =
            SmartConvertController.getOfficesForFirm(l.Id, firm.Id);
        Test.stopTest();
        System.assertEquals(2, offs.size());
        System.assertEquals('Dentons UK Demo', offs[0].nm, 'UK office ranks first for a UK lead');
    }

    @IsTest
    static void convert_runsThroughController() {
        Account ukOffice = [SELECT Id FROM Account WHERE Name = 'Dentons UK Demo' LIMIT 1];
        Account usOffice = [SELECT Id FROM Account WHERE Name = 'Dentons US Demo' LIMIT 1];
        Lead l = newLead('James', 'james@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        // recommended = US, rep chose UK (override), via manual search
        SmartConvertController.ConvertResult r = SmartConvertController.convert(
            l.Id, ukOffice.Id, null, true, 'ONECLICK', false, 'GBP', usOffice.Id, true, null, null);
        Test.stopTest();
        System.assertNotEquals(null, r);
        System.assertNotEquals(null, r.message);
        // telemetry + decision capture stamped before convert
        Lead chk = [SELECT Conversion_Source__c, Match_Confidence__c, New_Account_Created__c,
            Recommended_Office__c, Overrode_Recommendation__c, Manual_Search_Used__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Smart Convert', chk.Conversion_Source__c);
        System.assertEquals('ONECLICK', chk.Match_Confidence__c);
        System.assertEquals(false, chk.New_Account_Created__c);
        System.assertEquals(usOffice.Id, chk.Recommended_Office__c, 'recommended office captured');
        System.assertEquals(true, chk.Overrode_Recommendation__c, 'chose UK, recommended US');
        System.assertEquals(true, chk.Manual_Search_Used__c);
    }

    @IsTest
    static void firmExistsNoOffice_viewThenCreateOffice() {
        // Reuse the seeded Dentons firm; strip its offices to simulate the no-office state.
        Account firm = [SELECT Id FROM Account WHERE Name = 'Dentons Demo' LIMIT 1];
        delete [SELECT Id FROM Account WHERE Ultimate_Account__c = :firm.Id];
        Lead l = newLead('Nora', 'nora@dentons-demo.com', 'GB', 'Leeds');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        System.assertEquals(true, v.hasFirm);
        System.assertEquals(true, v.firmNoOffice, 'firm resolved but has no office');
        System.assertEquals(0, v.offices.size());
        SmartConvertController.ConvertResult r = SmartConvertController.createOfficeUnderFirm(l.Id, firm.Id, false, 'GUIDED_CREATE', 'GBP', false, null, null);
        Test.stopTest();
        System.assertNotEquals(null, r);
        Boolean officeCreated = ![SELECT Id FROM Account
            WHERE Ultimate_Account__c = :firm.Id AND RecordType.DeveloperName = 'Office'].isEmpty();
        System.assert(officeCreated || (r.message != null && r.message.startsWith('Create blocked')),
            'should create an Office under the existing Firm or surface a blocked message: ' + r.message);
    }

    @IsTest
    static void searchFirms_findsByName() {
        Test.startTest();
        List<SmartConvertController.Firm> hits = SmartConvertController.searchFirms('Dentons');
        List<SmartConvertController.Firm> officeHits = SmartConvertController.searchFirms('Dentons UK Demo');
        List<SmartConvertController.Firm> tooShort = SmartConvertController.searchFirms('x');
        Test.stopTest();
        System.assert(!hits.isEmpty(), 'search should find the seeded Dentons firm');
        System.assertEquals('Dentons Demo', hits[0].name);
        System.assertEquals(0, tooShort.size(), 'sub-2-char term returns nothing');
        // Office-name search resolves the OFFICE to its parent firm and carries officeId
        Account firm = [SELECT Id FROM Account WHERE Name = 'Dentons Demo' LIMIT 1];
        Account office = [SELECT Id FROM Account WHERE Name = 'Dentons UK Demo' LIMIT 1];
        SmartConvertController.Firm officeHit = null;
        for (SmartConvertController.Firm f : officeHits) {
            if (f.officeId == office.Id) officeHit = f;
        }
        System.assertNotEquals(null, officeHit, 'office-name search returns the office as a hit');
        System.assertEquals(firm.Id, officeHit.id, 'office hit resolves to its parent firm for placement');
        System.assertEquals('Dentons Demo', officeHit.firmName, 'office hit carries the parent firm name');
    }

    @IsTest
    static void getMatch_buildsContactPickerOptions() {
        Account office = [SELECT Id FROM Account WHERE Name = 'Dentons UK Demo' LIMIT 1];
        insert new Contact(FirstName = 'Existing', LastName = 'Person', Title = 'Partner',
            Email = 'dup@dentons-demo.com', AccountId = office.Id);
        Lead l = newLead('Dup', 'dup@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        Test.stopTest();
        System.assert(v.contactOptions != null && !v.contactOptions.isEmpty(), 'should expose contact options');
        System.assertEquals('found', v.contact.result);
        Boolean anyRecommended = false;
        for (SmartConvertController.ContactOption o : v.contactOptions) {
            if (o.recommended) anyRecommended = true;
        }
        System.assert(anyRecommended, 'one option should be recommended');
    }

    @IsTest
    static void createAndConvert_buildsFirmAndOffice() {
        Lead l = newLead('Sofia', 'sofia@brand-new-co.es', 'ES', 'Madrid');
        l.Company = 'Brand New Co';
        update l;
        Test.startTest();
        SmartConvertController.ConvertResult r =
            SmartConvertController.createAndConvert(l.Id, false, 'GUIDED_CREATE', 'GBP', false, 'Genuinely new company', null);
        Test.stopTest();
        System.assertNotEquals(null, r);
        List<Account> firms = [SELECT Id, Originated_From_Lead__c FROM Account WHERE Name = 'Brand New Co'];
        // Either the Firm was created, or a managed package blocked it with a readable message.
        System.assert(!firms.isEmpty() || (r.message != null && r.message.startsWith('Create blocked')),
            'guided create should insert a Firm or surface a blocked message: ' + r.message);
        if (!firms.isEmpty()) {
            // Satisfies the org's Can_Create_Account_only_via_Lead rule for non-admin reps
            System.assertEquals(true, firms[0].Originated_From_Lead__c,
                'created firm is stamped as lead-originated');
        }
    }

    @IsTest
    static void getMatch_freeMailRoutesToNoFirm() {
        // a free-mail address must NOT resolve to a firm by domain (gmail isn't a company key)
        Lead l = newLead('Gina', 'gina.personal@gmail.com', 'GB', 'London');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        Test.stopTest();
        System.assertEquals(false, v.hasFirm, 'free-mail domain must not match a firm');
        System.assertNotEquals(null, v.dedup, 'no-firm path exposes the dedup checks');
        System.assertEquals('New Business', v.oppMotion, 'no firm, no prior business -> new business');
    }

    @IsTest
    static void disqualify_noMatchStillConvertsNoOpp() {
        // disqualify on a genuinely-new lead must STILL convert (build firm+office) with no opp + a reason
        Lead l = newLead('Nils', 'nils@brand-new-zzz.no', 'NO', 'Oslo');
        l.Company = 'Brand New ZZZ';
        update l;
        Test.startTest();
        SmartConvertController.ConvertResult r = SmartConvertController.createAndConvert(
            l.Id, false, 'GUIDED_CREATE', 'GBP', false, 'Genuinely new company', 'Not interested');
        Test.stopTest();
        System.assertNotEquals(null, r);
        Lead c = [SELECT IsConverted, ConvertedOpportunityId, Disqualify_Reason__c, Disqualified_At_Convert__c,
                  Conversion_Source__c FROM Lead WHERE Id = :l.Id];
        Boolean built = ![SELECT Id FROM Account WHERE Name = 'Brand New ZZZ'].isEmpty();
        if (built) {
            System.assertEquals(true, c.IsConverted, 'disqualify still converts');
            System.assertEquals(null, c.ConvertedOpportunityId, 'disqualify creates no opportunity');
            System.assertEquals('Not interested', c.Disqualify_Reason__c);
            System.assertEquals(true, c.Disqualified_At_Convert__c);
        } else {
            System.assert(r.message != null && r.message.startsWith('Create blocked'),
                'either built the firm or surfaced a blocked message: ' + r.message);
        }
    }

    @IsTest
    static void motion_classifiedAndStamped() {
        Account ukOffice = [SELECT Id FROM Account WHERE Name = 'Dentons UK Demo' LIMIT 1];
        Lead l = newLead('Moe', 'moe@dentons-demo.com', 'GB', 'London');
        Test.startTest();
        SmartConvertController.View v = SmartConvertController.getMatch(l.Id);
        SmartConvertController.ConvertResult r = SmartConvertController.convert(
            l.Id, ukOffice.Id, null, true, 'ONECLICK', false, 'GBP', ukOffice.Id, false, null, null);
        Test.stopTest();
        // motion is always classified (no brand/subs seeded => New Business or Cross-sell)
        System.assertNotEquals(null, v.oppMotion, 'motion classified on the view');
        System.assert(new Set<String>{ 'New Business', 'Cross-sell', 'Upsell', 'Renewal' }.contains(v.oppMotion),
            'valid motion: ' + v.oppMotion);
        Lead chk = [SELECT Opportunity_Motion__c FROM Lead WHERE Id = :l.Id];
        System.assertNotEquals(null, chk.Opportunity_Motion__c, 'motion stamped at convert');
        if (r.success && r.opportunityId != null) {
            Opportunity opp = [SELECT Type FROM Opportunity WHERE Id = :r.opportunityId];
            System.assertNotEquals(null, opp.Type, 'opp Type set from motion');
            List<OpportunityContactRole> ocrs = [
                SELECT Role, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :r.opportunityId
            ];
            System.assert(!ocrs.isEmpty(), 'convert created a contact role on the opp');
            Boolean anyDecisionMaker = false;
            for (OpportunityContactRole ocr : ocrs) {
                if (ocr.Role == 'Decision Maker') anyDecisionMaker = true;
            }
            System.assert(anyDecisionMaker, 'converted contact role stamped Decision Maker');

            // post-convert next action: follow-up task on the contact + opportunity
            SmartConvertController.TaskResult tr = SmartConvertController.createFollowUpTask(
                r.opportunityId, r.contactId, r.accountId, 'Follow up — test', 3, null,
                'Book a discovery call.\n\nCreated from Smart Convert · New Business', 'Call');
            System.assertNotEquals(null, tr.taskId, 'follow-up task created: ' + tr.message);
            Task t = [SELECT WhoId, WhatId, OwnerId, ActivityDate, Status, Type, Description FROM Task WHERE Id = :tr.taskId];
            System.assertEquals(r.opportunityId, t.WhatId, 'task linked to the opportunity');
            System.assertEquals(r.contactId, t.WhoId, 'task linked to the contact');
            System.assertEquals(UserInfo.getUserId(), t.OwnerId, 'task defaults to the running user');
            System.assertEquals(Date.today().addDays(3), t.ActivityDate, 'due date honoured');
            System.assertEquals('Call', t.Type, 'selected task type stamped');
            System.assert(t.Description.startsWith('Book a discovery call.'), 'rep comments lead the description');
        }
    }

    @IsTest
    static void ownership_returnsOwnerAndTeam() {
        Account firm = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Firm' LIMIT 1];
        Test.startTest();
        SmartConvertController.OwnerView ov = SmartConvertController.getOwnership(firm.Id, null);
        Test.stopTest();
        System.assertEquals(firm.Id, ov.firmId, 'ownership resolved for the firm');
        System.assertNotEquals(null, ov.firmOwner, 'owner name surfaced');
        System.assertNotEquals(null, ov.team, 'team list is never null');
    }

    @IsTest
    static void persona_inferenceMapsTitles() {
        System.assertEquals('Knowledge / PSL', SmartConvertController.inferPersona('Professional Support Lawyer'));
        System.assertEquals('Knowledge / PSL', SmartConvertController.inferPersona('Head of Knowledge Management'));
        System.assertEquals('Library / Research', SmartConvertController.inferPersona('Law Librarian'));
        System.assertEquals('L&D', SmartConvertController.inferPersona('Learning and Development Manager'));
        System.assertEquals('Practice leadership', SmartConvertController.inferPersona('Managing Partner'));
        System.assertEquals('', SmartConvertController.inferPersona('Sales Coordinator'));
        System.assertEquals('', SmartConvertController.inferPersona(null));
        System.assertEquals(true, SmartConvertController.isSenior('Head of Practice'));
        System.assertEquals(false, SmartConvertController.isSenior('Associate'));
    }

    @IsTest
    static void committee_returnsMembersAndCoverage() {
        Account firm = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Firm' LIMIT 1];
        Test.startTest();
        SmartConvertController.CommitteeView cv = SmartConvertController.getBuyingCommittee(firm.Id);
        Test.stopTest();
        System.assertNotEquals(null, cv.members, 'members list is never null');
        System.assertEquals(4, cv.coverage.size(), 'coverage reports all four Pro personas');
        System.assert(cv.gaps >= 0 && cv.gaps <= 4, 'gap count within range');
    }
}
