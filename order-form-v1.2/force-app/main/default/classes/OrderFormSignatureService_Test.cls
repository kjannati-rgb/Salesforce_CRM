@IsTest
private class OrderFormSignatureService_Test {

    @TestSetup
    static void setup() {
        // Standard org bypass so unrelated automation stays out of the way.
        insert new Application_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Disable_Triggers__c = false,
            Disable_Validation_Rules__c = true,
            Disable_Process_Builders__c = true,
            Disable_Approval_Processes__c = true
        );

        Account account = new Account(Name = 'OrderForm Test Account');
        insert account;
        Contact signatory = new Contact(LastName = 'Signatory', Email = 'signer@example.com', AccountId = account.Id);
        insert signatory;
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__PrimaryContact__c = signatory.Id
        );
        insert quote;
        // The CPQ package forces new quotes to Draft on insert - set Approved afterwards.
        quote.SBQQ__Status__c = 'Approved';
        update quote;
        insert new SBQQ__QuoteDocument__c(Name = 'Order Form v1.2 Test Doc', SBQQ__Quote__c = quote.Id);
        insert new echosign_dev1__Agreement_Template__c(
            Name = 'Order Form v1.2 - Subscription',
            echosign_dev1__Active__c = true
        );
    }

    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id, SBQQ__Status__c, Signatory_Contact__c FROM SBQQ__Quote__c LIMIT 1];
    }

    private static OrderFormSignatureService.Result run(Id quoteId) {
        OrderFormSignatureService.Request request = new OrderFormSignatureService.Request();
        request.quoteId = quoteId;
        return OrderFormSignatureService.send(new List<OrderFormSignatureService.Request>{ request })[0];
    }

    private static Order_Form_Settings__mdt activeSettings() {
        return new Order_Form_Settings__mdt(
            DeveloperName = 'Default',
            Active__c = true,
            Agreement_Template_Name__c = 'Order Form v1.2 - Subscription'
        );
    }

    @IsTest
    static void sendsWhenAllPreconditionsMet() {
        OrderFormSignatureService.settingsOverride = activeSettings();
        // Signatory is defaulted from the primary contact by the stamping flow on insert.
        SBQQ__Quote__c quote = getQuote();
        System.assertNotEquals(null, quote.Signatory_Contact__c, 'Stamping flow should default the signatory');

        Test.startTest();
        OrderFormSignatureService.Result result = run(quote.Id);
        Test.stopTest();

        System.assert(result.success, 'Expected success, got: ' + result.message);
    }

    @IsTest
    static void failsWhenKillSwitchOff() {
        Order_Form_Settings__mdt off = activeSettings();
        off.Active__c = false;
        OrderFormSignatureService.settingsOverride = off;

        OrderFormSignatureService.Result result = run(getQuote().Id);

        System.assert(!result.success);
        System.assert(result.message.contains('switched off'), result.message);
    }

    @IsTest
    static void failsWhenQuoteNotApproved() {
        OrderFormSignatureService.settingsOverride = activeSettings();
        SBQQ__Quote__c quote = getQuote();
        quote.SBQQ__Status__c = 'Draft';
        update quote;

        OrderFormSignatureService.Result result = run(quote.Id);

        System.assert(!result.success);
        System.assert(result.message.contains('must be Approved'), result.message);
    }

    @IsTest
    static void failsWhenNoSignatory() {
        OrderFormSignatureService.settingsOverride = activeSettings();
        SBQQ__Quote__c quote = getQuote();
        quote.Signatory_Contact__c = null;
        quote.SBQQ__PrimaryContact__c = null; // stop the stamping flow re-defaulting it
        update quote;

        OrderFormSignatureService.Result result = run(quote.Id);

        System.assert(!result.success);
        System.assert(result.message.contains('Signatory'), result.message);
    }

    @IsTest
    static void failsWhenNoDocument() {
        OrderFormSignatureService.settingsOverride = activeSettings();
        delete [SELECT Id FROM SBQQ__QuoteDocument__c];

        OrderFormSignatureService.Result result = run(getQuote().Id);

        System.assert(!result.success);
        System.assert(result.message.contains('quote document'), result.message);
    }

    @IsTest
    static void failsWhenTemplateMissing() {
        Order_Form_Settings__mdt bogus = activeSettings();
        bogus.Agreement_Template_Name__c = 'No Such Template';
        OrderFormSignatureService.settingsOverride = bogus;

        OrderFormSignatureService.Result result = run(getQuote().Id);

        System.assert(!result.success);
        System.assert(result.message.contains('not found'), result.message);
    }

    @IsTest
    static void readsRealDefaultSettings() {
        // No settingsOverride: exercises the Order_Form_Settings__mdt.getInstance path
        // against the deployed Default record.
        OrderFormSignatureService.Result result = run(getQuote().Id);
        System.assert(result.success, 'Expected success via real CMDT, got: ' + result.message);
    }

    @IsTest
    static void packageCallFailureIsCaught() {
        // Let the real echosign_dev1 call run; without a linked Adobe Sign account it
        // either succeeds in creating the agreement or throws - the catch must contain it.
        OrderFormSignatureService.settingsOverride = activeSettings();
        OrderFormSignatureService.bypassTemplateService = false;

        Test.startTest();
        OrderFormSignatureService.Result result = run(getQuote().Id);
        Test.stopTest();

        System.assertNotEquals(null, result.success, 'Result must always carry an outcome');
        System.assertNotEquals(null, result.message, 'Result must always carry a message');
    }

    @IsTest
    static void failsWhenQuoteMissing() {
        OrderFormSignatureService.settingsOverride = activeSettings();
        SBQQ__Quote__c quote = getQuote();
        Id quoteId = quote.Id;
        delete [SELECT Id FROM SBQQ__QuoteDocument__c];
        delete quote;

        OrderFormSignatureService.Result result = run(quoteId);

        System.assert(!result.success);
        System.assert(result.message.contains('not found'), result.message);
    }
}
