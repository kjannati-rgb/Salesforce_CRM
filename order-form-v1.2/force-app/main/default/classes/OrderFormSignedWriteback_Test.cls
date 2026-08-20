@IsTest
private class OrderFormSignedWriteback_Test {

    @IsTest
    static void stampsDateAndFilesPdf() {
        Account acc = new Account(Name = 'Writeback Test Account');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Writeback Test Opp', StageName = 'Identify',
            CloseDate = Date.today().addDays(30), AccountId = acc.Id);
        insert opp;
        SBQQ__Quote__c quote = new SBQQ__Quote__c(SBQQ__Opportunity2__c = opp.Id, SBQQ__Account__c = acc.Id);
        insert quote;
        echosign_dev1__SIGN_Agreement__c ag = new echosign_dev1__SIGN_Agreement__c(
            Name = 'Order Form - Test - Q-000001', Quote__c = quote.Id,
            echosign_dev1__DateSigned__c = System.now());
        insert ag;
        insert new Attachment(ParentId = ag.Id, Name = 'Order Form - Test - Q-000001 - signed.pdf',
            Body = Blob.valueOf('PDF'), ContentType = 'application/pdf');

        OrderFormSignedWriteback.Request req = new OrderFormSignedWriteback.Request();
        req.agreementId = ag.Id;
        Test.startTest();
        OrderFormSignedWriteback.run(new List<OrderFormSignedWriteback.Request>{ req });
        // idempotency: second run must not duplicate the file
        OrderFormSignedWriteback.run(new List<OrderFormSignedWriteback.Request>{ req });
        Test.stopTest();

        SBQQ__Quote__c after = [SELECT Customer_Signed_Date__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals(Date.today(), after.Customer_Signed_Date__c, 'signed date stamped');
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :quote.Id],
            'signed PDF filed exactly once');
    }

    @IsTest
    static void ignoresAgreementWithoutQuote() {
        echosign_dev1__SIGN_Agreement__c ag = new echosign_dev1__SIGN_Agreement__c(Name = 'No quote');
        insert ag;
        OrderFormSignedWriteback.Request req = new OrderFormSignedWriteback.Request();
        req.agreementId = ag.Id;
        Test.startTest();
        OrderFormSignedWriteback.run(new List<OrderFormSignedWriteback.Request>{ req });
        Test.stopTest();
        System.assert(true, 'no exception on quote-less agreement');
    }
}
