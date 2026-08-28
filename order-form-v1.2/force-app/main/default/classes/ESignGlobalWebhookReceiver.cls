@RestResource(urlMapping='/eSignGlbWebhookEndpoint')
global class ESignGlobalWebhookReceiver { 
    
    @HttpPost
    global static void receiveWebhook() {
        
        RestRequest req = RestContext.request;
        String body = req.requestBody.toString();
        System.debug('Received webhook: ' + body);
        
        readRequestBody(body);
    }
    
    @future(callout=true)
    public static void readRequestBody(String body)
    {
        
        
        
        Object requestBodyObject = JSON.deserialize(body, ESignGlobalAgrViewHelper.EnvelopeStatusWrapper.class);
        ESignGlobalAgrViewHelper.EnvelopeStatusWrapper envelopeStatusDetail = (ESignGlobalAgrViewHelper.EnvelopeStatusWrapper) requestBodyObject;
        
        System.debug('Received webhook:envelopeStatusDetail ' + envelopeStatusDetail);
        
        
        String envelopeId = envelopeStatusDetail.eventPayload.envelopeId;
        String envelopeStatusCode = envelopeStatusDetail.eventPayload.envelopeStatus;
        
        if(!String.isEmpty(envelopeId))
        {
            List<eSignGlobal_Agreement__c> eSignGlobal_AgrList = new List<eSignGlobal_Agreement__c>();
            eSignGlobal_AgrList = [SELECT Id, Envelope_Status__c, Quote_Document__r.SBQQ__Opportunity__c,Date_of_out_for_signature__c,
                                   Quote_Document__r.SBQQ__Quote__c
                                   FROM eSignGlobal_Agreement__c WHERE Envelope_Id__c = :envelopeId LIMIT 1];
            
            Boolean getSignedDoc = false;
            if(envelopeStatusCode != NULL && (ESignGlobalAgrViewHelper.STATUS_CODE_MAP).containsKey(envelopeStatusCode))
            {
                /****
                if(eSignGlobal_AgrList[0].Envelope_Status__c != (ESignGlobalAgrViewHelper.STATUS_CODE_MAP).get(envelopeStatusCode))
                	getSignedDoc = true;
				****/
                eSignGlobal_AgrList[0].Envelope_Status__c = (ESignGlobalAgrViewHelper.STATUS_CODE_MAP).get(envelopeStatusCode);
             }
            else
                eSignGlobal_AgrList[0].Envelope_Status__c = NULL;
            
             
			List<eSignGlobal_Agreement_Event__c> agreementFinishEvents = [SELECT id FROM eSignGlobal_Agreement_Event__c 
                                                                          WHERE Event_Type__c =:'ENVELOPE_FINISH' AND eSignGlobal_Agreement__c =:eSignGlobal_AgrList[0].id];            
            if(agreementFinishEvents.size() == 0)
            	getSignedDoc = TRUE;    
           
            
            if(envelopeStatusDetail.event == 'ENVELOPE_FINISH' && getSignedDoc) // When Completed 
            {
                try
                {
                    getSignedFile(envelopeId, eSignGlobal_AgrList[0].Id, eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Opportunity__c);
                }
                catch(Exception Err)
                {
                    System.debug('ESignGlobalWebhookReceiver Error Message : '+Err.getMessage());
                    System.debug('ESignGlobalWebhookReceiver Error Line : '+Err.getLineNumber());

                    updateError(eSignGlobal_AgrList[0].Id, 'Error : Fail to get Signed Document | '+Err.getMessage() + ' | Line Number : '+Err.getLineNumber());

                }

                // Order Form v1.2 channel parity (Aug 2026): the Adobe path stamps the quote's
                // Customer_Signed_Date__c on signature - do the same when an eSign Global
                // envelope completes. Isolated so a quote validation failure cannot block the
                // signed-document filing above.
                if(eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__c != NULL)
                {
                    try
                    {
                        update new SBQQ__Quote__c(
                            Id = eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__c,
                            Customer_Signed_Date__c = Date.today());
                    }
                    catch(Exception quoteErr)
                    {
                        System.debug('ESignGlobalWebhookReceiver quote signed-date stamp failed : '+quoteErr.getMessage());
                    }
                }
            }
            update eSignGlobal_AgrList;
            
            if( (envelopeStatusDetail.event != 'ENVELOPE_FINISH') || (envelopeStatusDetail.event == 'ENVELOPE_FINISH' && getSignedDoc)  )
            {
                eSignGlobal_Agreement_Event__c agreementEvent = prepareAgreementEvent(eSignGlobal_AgrList[0], envelopeStatusDetail);
                insert agreementEvent;
            }
        }
    }
    
    public static eSignGlobal_Agreement_Event__c prepareAgreementEvent(eSignGlobal_Agreement__c eSignGlobalAgreement, 
                                                                       ESignGlobalAgrViewHelper.EnvelopeStatusWrapper envelopeStatusDetail) 
    {
    	eSignGlobal_Agreement_Event__c agreementEvent = new eSignGlobal_Agreement_Event__c();
        agreementEvent.eSignGlobal_Agreement__c = eSignGlobalAgreement.id;
        agreementEvent.Event_Type__c = envelopeStatusDetail.event;
        agreementEvent.Description__c = ESignGlobalAgrViewHelper.EVENT_TYPE_DESCRIPTION_MAP.get(agreementEvent.Event_Type__c);
        agreementEvent.Date__c = System.Now();
        
        ESignGlobalAgrViewHelper.EventPayloadSignerWrapper signerDetails;
        if(envelopeStatusDetail.event != 'ENVELOPE_START') {
        	signerDetails =  envelopeStatusDetail.eventPayload.signerInfo;   
        }
        if(signerDetails != NULL) {
            agreementEvent.User_Email__c = signerDetails.userEmail;    
            agreementEvent.User_Name__c= signerDetails.userName;    
            agreementEvent.Signer_Status__c = ESignGlobalAgrViewHelper.SIGNER_STATUS_CODE_MAP.get(signerDetails.signerStatus);
            agreementEvent.Sign_Order__c = Integer.valueOf(signerDetails.signOrder);
        }
        
        return agreementEvent;
    }
    
    
    public static void getSignedFile(String envelopeId, String recordId, String oppId)
    {
      
            // Get Access Token
            eSignGlobal_Configuration__c cusSetting = eSignGlobal_Configuration__c.getOrgDefaults();    
            HTTPResponse response1 = ESignGlobalApiCallout.getAccesToken(cusSetting);
            ESignGlobalAgrViewCtrl.ProcessApiResponseWrapper apiResponseProcess1 = ESignGlobalAgrViewCtrl.processResponse( response1, recordId , ESignGlobalAgrViewCtrl.GET_ACCES_TOKEN);
            String accessToken = apiResponseProcess1.resultValue;
            
            
            HTTPResponse response2 = ESignGlobalApiCallout.downloadSignedDocuments(cusSetting , accessToken, envelopeId); // Api call to fetch download url
            String fileDownloadUrl = processResponse(response2 , recordId); // Get download url from reponse.
            
            // Get the actual file from url and save it in salesforce
            ESignGlobalApiCallout.downloadAndSaveFile(fileDownloadUrl, recordId,oppId);
                
    }
    
    public static String processResponse(HTTPResponse res , String recordId)
    {
        if(res.getStatusCode() == 200)
        {
            Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody()); 
            if( (String)responseMap.get('message') == 'success')
            {
                Map<String,Object> dataObj = (Map<String,Object>)responseMap.get('data'); 
                return (String)dataObj.get('downloadUrl'); 
            }
            else
            {
                updateError( recordId,'Error : Fail to get Signed Document | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody());
            }
        }
        else
        {
            updateError( recordId, 'Error : Fail to get Signed Document | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody());
        }
        
        return null;
        
    }
    
    public static void updateError(String recordId, String error)
    {
        eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
        eSign.Id = recordId;
        eSign.Error__c = error;
        update eSign; 
    }
    
}