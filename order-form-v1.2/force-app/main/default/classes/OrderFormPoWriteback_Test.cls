@IsTest
private class OrderFormPoWriteback_Test {

    private class FormDataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().endsWith('/baseUris')) {
                res.setBody('{"apiAccessPoint":"https://api.eu2.echosign.com/"}');
            } else {
                res.setBody(String.fromCharArray(new List<Integer>{ 65279 })
                    + '"completed","email","role","first","last","title","company","agreementId","VAT_Registered","VAT_Number","PO_Required","PO_Number"\n'
                    + '"2026-08-21 10:00:00","k@x.com","SIGNER","Kam","J","Head","LBR","CBJCHBCA","Yes","GB 123 4567 89","Yes","PO-4471, rev 2"\n');
            }
            return res;
        }
    }

    private static echosign_dev1__SIGN_Agreement__c setup(String existingPo) {
        return setup(existingPo, null);
    }

    private static echosign_dev1__SIGN_Agreement__c setup(String existingPo, String existingAccountVat) {
        Account acc = new Account(Name = 'PO Writeback Test', Sales_Tax_Number__c = existingAccountVat);
        insert acc;
        Opportunity opp = new Opportunity(Name = 'PO Writeback Opp', StageName = 'Identify',
            CloseDate = Date.today().addDays(30), AccountId = acc.Id);
        insert opp;
        SBQQ__Quote__c quote = new SBQQ__Quote__c(SBQQ__Opportunity2__c = opp.Id, SBQQ__Account__c = acc.Id,
            PO_Number__c = existingPo);
        insert quote;
        echosign_dev1__SIGN_Agreement__c ag = new echosign_dev1__SIGN_Agreement__c(
            Name = 'PO test', Quote__c = quote.Id, echosign_dev1__Document_Key__c = 'CBJCHBCA');
        insert ag;
        return ag;
    }

    @IsTest
    static void writesSignerPoWhenQuoteBlank() {
        insert new Order_Form_Adobe_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Integration_Key__c = 'test-key');
        echosign_dev1__SIGN_Agreement__c ag = setup(null);
        Test.setMock(HttpCalloutMock.class, new FormDataMock());
        Test.startTest();
        System.enqueueJob(new OrderFormPoWriteback(ag.Id));
        Test.stopTest();
        SBQQ__Quote__c q = [SELECT PO_Number__c, PO_Required__c, VAT_Registered__c, Customer_VAT_Number_Captured__c,
            SBQQ__Account__r.Sales_Tax_Number__c, SBQQ__Account__r.Sales_Tax_Number_Source__c
            FROM SBQQ__Quote__c WHERE Id = :ag.Quote__c];
        System.assertEquals('PO-4471, rev 2', q.PO_Number__c);
        System.assertEquals('Yes', q.PO_Required__c, 'signer answer to the PO-required question captured');
        System.assertEquals('Yes', q.VAT_Registered__c, 'VAT-registered answer captured');
        System.assertEquals('GB 123 4567 89', q.Customer_VAT_Number_Captured__c, 'typed VAT captured on the quote');
        System.assertEquals('GB 123 4567 89', q.SBQQ__Account__r.Sales_Tax_Number__c, 'blank account VAT filled');
        System.assert(q.SBQQ__Account__r.Sales_Tax_Number_Source__c.startsWith('Customer-signed Order Form'), 'provenance note written');
    }

    @IsTest
    static void neverOverwritesAccountVat() {
        insert new Order_Form_Adobe_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Integration_Key__c = 'test-key');
        echosign_dev1__SIGN_Agreement__c ag = setup(null, '160 7529 10');
        Test.setMock(HttpCalloutMock.class, new FormDataMock());
        Test.startTest();
        System.enqueueJob(new OrderFormPoWriteback(ag.Id));
        Test.stopTest();
        SBQQ__Quote__c q = [SELECT Customer_VAT_Number_Captured__c, SBQQ__Account__r.Sales_Tax_Number__c,
            SBQQ__Account__r.Sales_Tax_Number_Source__c FROM SBQQ__Quote__c WHERE Id = :ag.Quote__c];
        System.assertEquals('160 7529 10', q.SBQQ__Account__r.Sales_Tax_Number__c, 'Finance-validated account VAT untouched');
        System.assertEquals(null, q.SBQQ__Account__r.Sales_Tax_Number_Source__c, 'no provenance note when nothing written');
        System.assertEquals('GB 123 4567 89', q.Customer_VAT_Number_Captured__c, 'signer value still captured on the quote for review');
    }

    @IsTest
    static void neverOverwritesExistingPo() {
        insert new Order_Form_Adobe_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Integration_Key__c = 'test-key',
            API_Base_URI__c = 'https://api.eu2.echosign.com/');
        echosign_dev1__SIGN_Agreement__c ag = setup('KJ00001');
        Test.setMock(HttpCalloutMock.class, new FormDataMock());
        Test.startTest();
        System.enqueueJob(new OrderFormPoWriteback(ag.Id));
        Test.stopTest();
        SBQQ__Quote__c q = [SELECT PO_Number__c, PO_Required__c FROM SBQQ__Quote__c WHERE Id = :ag.Quote__c];
        System.assertEquals('KJ00001', q.PO_Number__c);
        System.assertEquals('Yes', q.PO_Required__c, 'answer still captured even when the PO itself stands');
    }

    @IsTest
    static void skipsWhenNotConfigured() {
        echosign_dev1__SIGN_Agreement__c ag = setup(null);
        Test.startTest();
        System.assertEquals(false, OrderFormPoWriteback.isConfigured());
        System.enqueueJob(new OrderFormPoWriteback(ag.Id));
        Test.stopTest();
        System.assertEquals(null, [SELECT PO_Number__c FROM SBQQ__Quote__c WHERE Id = :ag.Quote__c].PO_Number__c);
    }

    @IsTest
    static void csvParsingHandlesQuotesAndCommas() {
        String csv = String.fromCharArray(new List<Integer>{ 65279 }) + '"a","PO_Number","c"\n"1","x, ""y""","3"\n';
        System.assertEquals('x, "y"', OrderFormPoWriteback.csvField(csv, 'PO_Number'));
        System.assertEquals(null, OrderFormPoWriteback.csvField(csv, 'missing'));
        System.assertEquals(null, OrderFormPoWriteback.csvField('"only header"', 'a'));
    }
}
