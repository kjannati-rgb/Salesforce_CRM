/**
 * Integration test for the Data Team "Account is not complete" alert as it actually fires:
 * through the Opportunity master flow, not by calling the Apex directly.
 *
 * DataTeamEnrichNotifierTest covers the Apex in isolation. It would still pass if someone
 * deleted the flow's suppression conditions, changed the missing_fields_list formula, or
 * repointed the action - which is the regression most likely to happen, because that flow
 * is edited constantly for unrelated reasons. This test exercises the decision, the
 * suppression and the Apex call as one path.
 *
 * SeeAllData is required: the flow hardcodes the template DeveloperName
 * 'Data_Team_Enrich_Account' and the group 'Data_Team', both of which are org metadata the
 * test cannot create. If either is missing the notifier skips silently and the email-count
 * assertions fail - so these assertions also prove both still exist and are reachable.
 *
 * Automation flags: bypassValidationKeepMasterFlow() sets Disable_Validation_Rules__c (so the
 * Opportunity insert survives the org's VRs) and Disable_Autolaunch_Lightning_Flow__c (to
 * quieten unrelated subflows), while forcing Disable_Process_Builders__c OFF. That last flag
 * is the one the master flow's own CheckAutomationDisabled formula reads - leaving it on
 * would switch off the very flow under test and every assertion here would pass vacuously.
 */
@isTest(SeeAllData=true)
private class DataTeamEnrichAlertFlowTest {

    /**
     * TestDataFactory.bypassAutomation() cannot be used here: it inserts a fresh org-level
     * Application_Settings__c, and under SeeAllData the real one already exists, so the
     * upsert fails with DUPLICATE_VALUE on SetupOwnerId. Reuse the existing row instead.
     *
     * Disable_Process_Builders__c is forced to false rather than left alone - it is the flag
     * the master flow reads, so inheriting a true value from the org would silently disable
     * the flow under test and make every assertion here pass for the wrong reason.
     */
    private static void bypassValidationKeepMasterFlow() {
        List<Application_Settings__c> existing =
            [SELECT Id FROM Application_Settings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId()];
        Application_Settings__c s = existing.isEmpty()
            ? new Application_Settings__c(SetupOwnerId = UserInfo.getOrganizationId())
            : existing[0];
        s.Disable_Validation_Rules__c = true;
        s.Disable_Autolaunch_Lightning_Flow__c = true;
        s.Disable_Process_Builders__c = false;
        upsert s;
    }

    private static User userOnProfile(String profileName, String aliasSeed) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
            String stamp = String.valueOf(Datetime.now().getTime()).right(8);
            u = new User(
                FirstName = 'DTE', LastName = aliasSeed,
                Email = aliasSeed + '.dte@example.com',
                Username = aliasSeed + '.dte.' + stamp + '@example.com.dteflow',
                Alias = (aliasSeed + '000').left(8),
                ProfileId = p.Id, IsActive = true,
                TimeZoneSidKey = 'Europe/London', LocaleSidKey = 'en_GB',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            insert u;
        }
        return u;
    }

    private static Account accountMissing(Boolean country, Boolean city, Boolean street) {
        Account a = new Account(
            Name = 'DTE Flow Test Account',
            BillingCountry = country ? null : 'United Kingdom',
            BillingCity    = city    ? null : 'London',
            BillingStreet  = street  ? null : '1 Test Street'
        );
        insert a;
        return a;
    }

    private static Opportunity newOpp(Id accountId) {
        return new Opportunity(
            Name = 'DTE Flow Test Opp',
            AccountId = accountId,
            StageName = 'Qualify',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = 'GBP'
        );
    }

    /**
     * The headline case that could never be tested from the CLI: a sales user creates an
     * Opportunity on an account missing exactly ONE billing field.
     */
    @isTest
    static void alertFiresForSalesUserWithSingleMissingField() {
        bypassValidationKeepMasterFlow();
        User sales = userOnProfile('Custom: Sales Profile', 'sales1');
        Account a = accountMissing(false, true, false); // only Billing City blank

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        System.runAs(sales) {
            insert newOpp(a.Id);
        }
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assert(after > before,
            'A sales user creating an Opportunity on an account with a blank Billing City '
            + 'should trigger the Data Team alert. Email invocations before=' + before
            + ' after=' + after);
    }

    /** All three blank - the case every earlier test used. */
    @isTest
    static void alertFiresWhenAllThreeMissing() {
        bypassValidationKeepMasterFlow();
        User sales = userOnProfile('Custom: Sales Profile', 'sales2');
        Account a = accountMissing(true, true, true);

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        System.runAs(sales) {
            insert newOpp(a.Id);
        }
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assert(after > before, 'All three fields blank should trigger the alert.');
    }

    /** A complete billing address must not alert, regardless of who creates the opp. */
    @isTest
    static void noAlertWhenAddressComplete() {
        bypassValidationKeepMasterFlow();
        User sales = userOnProfile('Custom: Sales Profile', 'sales3');
        Account a = accountMissing(false, false, false);

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        System.runAs(sales) {
            insert newOpp(a.Id);
        }
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(before, after,
            'A complete billing address must not send the Data Team alert.');
    }

    /**
     * The suppression, which is the half that cannot be exercised from the CLI at all -
     * every deploy runs as System Administrator, so this path is invisible in manual testing.
     */
    @isTest
    static void suppressedForSystemAdministratorCreator() {
        bypassValidationKeepMasterFlow();
        User admin = userOnProfile('System Administrator', 'admin1');
        Account a = accountMissing(true, true, true);

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        System.runAs(admin) {
            insert newOpp(a.Id);
        }
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(before, after,
            'An Opportunity created by a System Administrator must be suppressed.');
    }

    @isTest
    static void suppressedForDataManagementCreator() {
        bypassValidationKeepMasterFlow();
        User dataUser = userOnProfile('Custom: Data Management', 'datam1');
        Account a = accountMissing(true, true, true);

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        System.runAs(dataUser) {
            insert newOpp(a.Id);
        }
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(before, after,
            'An Opportunity created by Custom: Data Management must be suppressed.');
    }
}
