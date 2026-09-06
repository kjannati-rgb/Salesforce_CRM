@isTest
public class ESignGlobalWebhookReceiverTest {

    class MockSuccessHttpCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();

            if (req.getEndpoint().contains('token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token":"mockToken"}');
            } else if (req.getEndpoint().contains('download-signed')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"message":"success","data":{"downloadUrl":"https://mocklink.com/sample.pdf"}}');
            } else if (req.getEndpoint().contains('sample.pdf')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf('Mock PDF content'));
            }else if (req.getEndpoint().contains('keywordPositions')) {
                res.setBody('{"data":[{"keyword":"{{ESG_Signer_1}}","positions":[{"pageNum":1,"coordinates":[{"positionX":"100","positionY":"200"}]}]},{"keyword":"{{Sig_es_:signer1:signature}}","positions":[{"pageNum":1,"coordinates":[{"positionX":"120","positionY":"220"}]}]}]}');
            } 

            return res;
        }
    }

    class MockErrorHttpCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();

            if (req.getEndpoint().contains('token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token":"mockToken"}');
            } else if (req.getEndpoint().contains('download-signed')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"message":"error","data":{}}');
            } else if (req.getEndpoint().contains('envelope/cancel')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/pdf');
                res.setBody('{"message": "success"}');
            } else {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"data":[{"keyword":"{{ESG_Signer_1}}","positions":[{"pageNum":1,"coordinates":[{"positionX":"100","positionY":"200"}]}]},{"keyword":"{{Sig_es_:signer1:signature}}","positions":[{"pageNum":1,"coordinates":[{"positionX":"120","positionY":"220"}]}]}]}');
            }

            return res;
        }
    }

    static Id setupTestData(String envelopeId, String contactEmail) {
        insert new eSignGlobal_Configuration__c(
            Name = 'Default',
            Client_Id__c = 'client-id',
            Client_Secret__c = 'client-secret'
        );

        Account acc = new Account(Name = 'Test Account', BillingCountry = 'India');
        insert acc;

        Contact con = new Contact(LastName = 'Test User', Email = contactEmail, AccountId = acc.Id);
        insert con;

        SBQQ__Quote__c quote = new SBQQ__Quote__c( SBQQ__PrimaryContact__c = con.Id);
        insert quote;

        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name = 'Quote Doc Test', SBQQ__Quote__c = quote.Id
        );
        insert quoteDoc;

        eSignGlobal_Agreement__c agreement = new eSignGlobal_Agreement__c(
            Envelope_Id__c = envelopeId,
            Envelope_Status__c = 'SENT',
            Quote_Document__c = quoteDoc.Id
        );
        insert agreement;

        return agreement.Id;
    }

    @isTest
    static void testReceiveWebhook_SuccessDownload() {
        Test.setMock(HttpCalloutMock.class, new MockSuccessHttpCallout());

        String envelopeId = 'envSuccess';
        setupTestData(envelopeId, 'test@success.com');

        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'ENVELOPE_FINISH',
            'eventPayload' => new Map<String, Object>{
                'envelopeId' => envelopeId,
                'envelopeStatus' => 2 // Must match what's in STATUS_CODE_MAP
            }
        };

        RestContext.request = new RestRequest();
        RestContext.request.requestUri = '/services/apexrest/eSignGlbWebhookEndpoint';
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        ESignGlobalWebhookReceiver.receiveWebhook();
        Test.stopTest();

        eSignGlobal_Agreement__c result = [
            SELECT Envelope_Status__c, Error__c FROM eSignGlobal_Agreement__c
            WHERE Envelope_Id__c = :envelopeId LIMIT 1
        ];
        System.assertEquals('Completed', result.Envelope_Status__c, 'Envelope_Status__c should be set');
        //System.assertEquals(null, result.Error__c, 'Error__c should be null');
    }

    @isTest
    static void testReceiveWebhook_DownloadFails() {
        Test.setMock(HttpCalloutMock.class, new MockErrorHttpCallout());

        String envelopeId = 'envError';
        setupTestData(envelopeId, 'test@error.com');
		/*
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'ENVELOPE_FINISH',
            'eventPayload' => new Map<String, Object>{
                'envelopeId' => envelopeId,
                'envelopeStatus' => 2
            }
        };
		*/
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'ENVELOPE_FINISH',
            'eventPayload' => new Map<String, Object>{
                'envelopeId' => envelopeId,
                'envelopeStatus' => 2
            },
            'data' => new List<Object>{
                new Map<String, Object>{
                    'keyword' => '{{ESG_Signer_1}}',
                    'positions' => new List<Object>{
                        new Map<String, Object>{
                            'pageNum' => 1,
                            'coordinates' => new List<Object>{
                                new Map<String, Object>{
                                    'positionX' => '100',
                                    'positionY' => '200'
                                }
                            }
                        }
                    }
                },
                new Map<String, Object>{
                    'keyword' => '{{Sig_es_:signer1:signature}}',
                    'positions' => new List<Object>{
                        new Map<String, Object>{
                            'pageNum' => 1,
                            'coordinates' => new List<Object>{
                                new Map<String, Object>{
                                    'positionX' => '120',
                                    'positionY' => '220'
                                }
                            }
                        }
                    }
                }
            }
        };


        RestContext.request = new RestRequest();
        RestContext.request.requestUri = '/services/apexrest/eSignGlbWebhookEndpoint';
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        ESignGlobalWebhookReceiver.receiveWebhook();
        Test.stopTest();

        eSignGlobal_Agreement__c result = [
            SELECT Envelope_Status__c, Error__c FROM eSignGlobal_Agreement__c
            WHERE Envelope_Id__c = :envelopeId LIMIT 1
        ];

        System.assertEquals('Completed', result.Envelope_Status__c);
        //System.assertNotEquals(null, result.Error__c, 'Error__c should be populated');
    }
	/*
    @isTest
    static void testReceiveWebhook_EmptyPayloadHandled() {
        // Valid but empty JSON (not "")
        RestContext.request = new RestRequest();
        RestContext.request.requestUri = '/services/apexrest/eSignGlbWebhookEndpoint';
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = Blob.valueOf('{}');
        RestContext.response = new RestResponse();

        Test.startTest();
        ESignGlobalWebhookReceiver.receiveWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'Should not throw error for empty JSON');
    }
	*/
}