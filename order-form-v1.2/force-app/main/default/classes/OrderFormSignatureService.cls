/**
 * REV Order Form v1.2 - sends the subscription Order Form for Adobe Sign signature.
 * Thin invocable wrapper around echosign_dev1.AgreementTemplateService, shared by the
 * one-click quick action flow and the zero-click on-approval flow. The agreement template
 * is resolved by name from Order_Form_Settings__mdt (never hardcoded); the Default record's
 * Active__c flag is the kill switch.
 */
public with sharing class OrderFormSignatureService {

    public class Request {
        @InvocableVariable(label='Quote Id' required=true)
        public Id quoteId;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Agreement Id')
        public Id agreementId;
        @InvocableVariable(label='Message')
        public String message;
    }

    // The package call requires a linked Adobe Sign account, absent in dev sandboxes and
    // in test context - tests run everything up to the boundary and stub the call itself.
    @TestVisible
    private static Boolean bypassTemplateService = Test.isRunningTest();

    @TestVisible
    private static Order_Form_Settings__mdt settingsOverride;

    @InvocableMethod(
        label='Send Order Form for Signature'
        description='Creates and auto-sends the Order Form v1.2 Adobe Sign agreement for the given quote.')
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(sendOne(req.quoteId));
        }
        return results;
    }

    private static Result sendOne(Id quoteId) {
        Order_Form_Settings__mdt settings = settingsOverride != null
            ? settingsOverride
            : Order_Form_Settings__mdt.getInstance('Default');
        if (settings == null || !settings.Active__c) {
            return fail('Order Form signature sending is switched off (Order_Form_Settings.Default).');
        }

        List<SBQQ__Quote__c> quotes = [
            SELECT Id, SBQQ__Status__c, Signatory_Contact__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            return fail('Quote not found: ' + quoteId);
        }
        SBQQ__Quote__c quote = quotes[0];
        if (quote.SBQQ__Status__c != 'Approved') {
            return fail('The quote must be Approved before sending (current status: ' + quote.SBQQ__Status__c + ').');
        }
        if (quote.Signatory_Contact__c == null) {
            return fail('No Signatory Contact is set on the quote.');
        }
        if ([SELECT COUNT() FROM SBQQ__QuoteDocument__c WHERE SBQQ__Quote__c = :quoteId] == 0) {
            return fail('No generated quote document exists. Generate the Order Form PDF first.');
        }

        List<echosign_dev1__Agreement_Template__c> templates = [
            SELECT Id
            FROM echosign_dev1__Agreement_Template__c
            WHERE Name = :settings.Agreement_Template_Name__c
              AND echosign_dev1__Active__c = true
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return fail('Active agreement template "' + settings.Agreement_Template_Name__c + '" not found.');
        }

        Result result = new Result();
        try {
            if (!bypassTemplateService) {
                result.agreementId = echosign_dev1.AgreementTemplateService.load(
                    String.valueOf(templates[0].Id), String.valueOf(quoteId));
            }
            result.success = true;
            result.message = 'Agreement created and sent for signature.';
        } catch (Exception e) {
            result.success = false;
            result.message = 'Adobe Sign error: ' + e.getMessage();
        }
        return result;
    }

    private static Result fail(String message) {
        Result result = new Result();
        result.success = false;
        result.message = message;
        return result;
    }
}
