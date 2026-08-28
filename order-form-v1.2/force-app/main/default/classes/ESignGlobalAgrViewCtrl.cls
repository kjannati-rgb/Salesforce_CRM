public class ESignGlobalAgrViewCtrl {
    
    public static final String SUCCESS = '$UCCE$$';
    public static final String GET_ACCES_TOKEN = 'Get Acces Token';
    public static final String GET_UPLOAD_URL = 'Get Upload URL';
    public static final String UPLOAD_FILE = 'Upload File';
    public static final String GET_KEYWORD_POSITIONS = 'Get Keyword Positions';
    public static final String CREATE_ENVELOPE = 'Create Envelope';
    public static final String ADD_FILE_TO_ENVELOPE = 'Add File To Envelope';
    public static final String ADD_SIGNER = 'ADD SIGNER';
    public static final String ENVELOPE_SENDER_VIEW = 'Envelope Sender View';
    public static final String CANCEL_ENVELOPE = 'Cancel Envelope';
    public static final String RESEND_ENVELOPE = 'Resend Envelope';
    
    //  ESignGlobalAgrViewCtrl.runOnLoad('a6eUF0000002kErYAI');
    @AuraEnabled
    public static ResponseWrapper runOnLoad(String recordId) 
    {
        System.debug('recordId = '+ recordId);
        
        ResponseWrapper response = new ResponseWrapper();
        
        try
        {
            
            List<eSignGlobal_Agreement__c> eSignGlobal_AgrList = new List<eSignGlobal_Agreement__c>();
            eSignGlobal_AgrList = [SELECT Id, Name,Quote_Document__r.Name, Quote_Document__r.SBQQ__Quote__r.SBQQ__PrimaryContact__r.Name,
                                   Quote_Document__r.SBQQ__Quote__r.SBQQ__PrimaryContact__r.Email,
                                   Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Name,
                                   Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Email FROM eSignGlobal_Agreement__c WHERE Id = :recordId];
            
            eSignGlobal_Configuration__c cusSetting = eSignGlobal_Configuration__c.getOrgDefaults();        
            
            // GET ACCES TOKEN -----------------------------
            HTTPResponse response1 = ESignGlobalApiCallout.getAccesToken(cusSetting);
            ProcessApiResponseWrapper apiResponseProcess1 = processResponse( response1, recordId , GET_ACCES_TOKEN);
            String accessToken = apiResponseProcess1.resultValue;
            System.debug('accessToken=> '+ accessToken);
            
            //Get url to upload the File that needs to be send for signature------------------
            ProcessApiResponseWrapper apiResponseProcess2;
            String fileKey ;//= '$ac38d3aa-df64-4c4b-8a00-52c8dbf00f17$95040248';
            String fileUploadUrl;
            
            if(apiResponseProcess1.callNextApi)
            {
                HTTPResponse response2 = ESignGlobalApiCallout.getFileUploadUrl(cusSetting, accessToken, eSignGlobal_AgrList[0]);
                apiResponseProcess2 = processResponse( response2, recordId , GET_UPLOAD_URL);
                fileKey = apiResponseProcess2.fileKey;
                fileUploadUrl = apiResponseProcess2.resultValue;
            }
            
            
            //Upload the File that needs to be send for signature------------------
            ProcessApiResponseWrapper apiResponseProcess3;
            if(apiResponseProcess2 != null && apiResponseProcess2.callNextApi)
            {
                HTTPResponse response3 = ESignGlobalApiCallout.uploadDocToUrl( fileUploadUrl, accessToken, eSignGlobal_AgrList[0]);
                apiResponseProcess3 = processResponse( response3, recordId , UPLOAD_FILE);
            }
            
            // Get the position for signature blocks-------------------    
            ProcessApiResponseWrapper apiResponseProcess4;
            if(apiResponseProcess3 != null && apiResponseProcess3.callNextApi)  
            {
                HTTPResponse response4 = ESignGlobalApiCallout.getkeywordPositions(cusSetting, accessToken, fileKey);
                apiResponseProcess4 = processResponse( response4, recordId , GET_KEYWORD_POSITIONS);
                System.debug('apiResponseProcess4== '+apiResponseProcess4);
            }
            
            // Create Envelope --------------------------------------   
            ProcessApiResponseWrapper apiResponseProcess5;
            String envelopeId ;//= '921e5b04110c4ad6badadd3ed61797cb';
            
            if(apiResponseProcess4 != null && apiResponseProcess4.callNextApi)
            {
                HTTPResponse response5 = ESignGlobalApiCallout.createEnvelope(cusSetting, accessToken, eSignGlobal_AgrList[0], System.Label.ESignGlobal_Default_Subject);
                apiResponseProcess5 = processResponse( response5, recordId , CREATE_ENVELOPE);
                envelopeId = apiResponseProcess5.resultValue;
                System.debug(apiResponseProcess5);
            }
            
            // Add uploade file to Envelope -------------------------------------
            ProcessApiResponseWrapper apiResponseProcess6;
            if(apiResponseProcess5 != null && apiResponseProcess5.callNextApi) 
            {
                HTTPResponse response6 = ESignGlobalApiCallout.addDocuments(cusSetting , accessToken, fileKey, envelopeId);
                apiResponseProcess6 = processResponse( response6, recordId , ADD_FILE_TO_ENVELOPE);
            }
            
            // Add Signer detail to Envelope -------------------------------------
            ProcessApiResponseWrapper apiResponseProcess7;
             
             
            if(apiResponseProcess6 != null && apiResponseProcess6.callNextApi) 
            {
                // Order Form v1.2: the quote's Signatory Contact (rep-chosen signer) wins when it
                // has an email; legacy behaviour (primary contact) is the fallback.
                String signerEmail = eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Email != NULL
                    ? eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Email
                    : eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.SBQQ__PrimaryContact__r.Email;
                String signerName = eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Email != NULL
                    ? eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.Signatory_Contact__r.Name
                    : eSignGlobal_AgrList[0].Quote_Document__r.SBQQ__Quote__r.SBQQ__PrimaryContact__r.Name;
                if(signerEmail == NULL)
                    apiResponseProcess7.callNextApi = TRUE;
                else
                {
                    
                    List<ESignGlobalAgrViewHelper.SignConfigsWrapper> signConfig = new List<ESignGlobalAgrViewHelper.SignConfigsWrapper>();
                    List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper> signDateConfig = new List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper>();
                    List<ESignGlobalAgrViewHelper.FillConfigsWrapper> fillConfig = new List<ESignGlobalAgrViewHelper.FillConfigsWrapper>();
                    
                    if( apiResponseProcess4.signConfigMap != NULL &&  (apiResponseProcess4.signConfigMap).containsKey(ESignGlobalAgrViewHelper.SIGNER_1) &&
                       (apiResponseProcess4.signConfigMap).get(ESignGlobalAgrViewHelper.SIGNER_1) != null)
                        signConfig = apiResponseProcess4.signConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1);
                    
                    if( apiResponseProcess4.signDateConfigMap != NULL &&  (apiResponseProcess4.signDateConfigMap).containsKey(ESignGlobalAgrViewHelper.SIGNER_1_Date) &&
                       (apiResponseProcess4.signDateConfigMap).get(ESignGlobalAgrViewHelper.SIGNER_1_Date) != null)
                        signDateConfig = apiResponseProcess4.signDateConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1_Date);
                    
                    if( apiResponseProcess4.fillConfigMap != NULL &&  (apiResponseProcess4.fillConfigMap).containsKey(ESignGlobalAgrViewHelper.SIGNER_1_Name) &&
                       (apiResponseProcess4.fillConfigMap).get(ESignGlobalAgrViewHelper.SIGNER_1_Name) != null)
                        fillConfig = apiResponseProcess4.fillConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1_Name);
                    
                    System.debug('Signature==>signConfig '+signConfig);
                    System.debug('Signature==>signDateConfigs '+signDateConfig);
                     
                    // Prepare request body for adding signer
                    ESignGlobalAgrViewHelper.SealInfosWrapper sealInfos = new ESignGlobalAgrViewHelper.SealInfosWrapper();
                    List<ESignGlobalAgrViewHelper.SealInfosWrapper> sealInfosList = new List<ESignGlobalAgrViewHelper.SealInfosWrapper>();
                    sealInfos.fileKey = fileKey;
                    sealInfos.signConfigs = signConfig;
                    if(sealInfos.signConfigs == NULL || (sealInfos.signConfigs).size() == 0 )
                        sealInfos.signConfigs = ESignGlobalAgrViewHelper.defaultSignerBlockPosition();
                    sealInfos.signDateConfigs = signDateConfig;
                    sealInfos.fillConfigs = fillConfig;
                    sealInfosList.add(sealInfos);
                    system.debug('sealInfos=== '+sealInfos);
                    
                    ESignGlobalAgrViewHelper.SignerInfoWrapper signerInfo = new ESignGlobalAgrViewHelper.SignerInfoWrapper();
                    signerInfo.userEmail = signerEmail;
                    signerInfo.userName = signerName;
                    signerInfo.signOrder = 1;
                    signerInfo.authModes = '0';
                    signerInfo.sealInfos = sealInfosList;
                    
                    List<ESignGlobalAgrViewHelper.SignerInfoWrapper> signerInfoList = new List<ESignGlobalAgrViewHelper.SignerInfoWrapper>();
                    signerInfoList.add(signerInfo);
                    
                    ESignGlobalAgrViewHelper.SignerRequestWrapper signerRequest = new ESignGlobalAgrViewHelper.SignerRequestWrapper();
                    signerRequest.envelopeId = envelopeId;
                    signerRequest.signerInfos = signerInfoList;
                    
                    // Send Signer detail in api request to add to envelope---------------
                    HTTPResponse response7 = ESignGlobalApiCallout.addSignatories( cusSetting , accessToken, signerRequest );
                    apiResponseProcess7 = processResponse( response7, recordId , ADD_SIGNER);
                     
                }
            }
            
             
            // Get the url for preview and sending document for signature 
            String senderViewUrl;
            ProcessApiResponseWrapper apiResponseProcess8;
            if(apiResponseProcess7 != null && apiResponseProcess7.callNextApi) 
            {
                
                URL baseUrl = URL.getOrgDomainUrl();
                String returnUrl = baseUrl.toExternalForm()+'/'+recordId;
                System.debug(returnUrl);
                
                HTTPResponse response8 = ESignGlobalApiCallout.envelopeSenderView(cusSetting , accessToken, envelopeId,returnUrl);
                apiResponseProcess8 = processResponse( response8, recordId , ENVELOPE_SENDER_VIEW);
                System.debug('apiResponseProcess8 == '+apiResponseProcess8);
                senderViewUrl = apiResponseProcess8.resultValue;
            }
            
            
            
            
            
            response.responseMsg = SUCCESS;
            response.senderViewUrl = senderViewUrl;
            
            eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
            eSign.Id = recordId;
            eSign.Error__c = null;
            eSign.Envelope_Status__c = 'Draft';
            eSign.Envelope_Id__c = envelopeId;
            update eSign;
        }
        catch(Exception Err)
        {
            System.debug(Err.getMessage());
            System.debug(Err.getLineNumber());
           
            String msg = Err.getMessage();
            System.debug(msg);
            msg = msg.replace('{', '|'); 
            msg = msg.replace('}', '|');
            
            response.responseMsg =  msg;  
      
        }
        
        return response;
    }
    
    public class ResponseWrapper
    {
        @AuraEnabled public String responseMsg {get;Set;}
        @AuraEnabled public String senderViewUrl {get;Set;}
    }
    
     @AuraEnabled
    public static ResponseWrapper cancelEnvelope( String recordId, String cancelReason )
    {
        ResponseWrapper response = new ResponseWrapper();
        response.responseMsg = SUCCESS;
        try
        {
             System.debug('recordId '+recordId);
            System.debug('cancelReason '+cancelReason);
            List<eSignGlobal_Agreement__c> eSignGlobal_AgrList = new List<eSignGlobal_Agreement__c>();
            eSignGlobal_AgrList = [SELECT Id, Envelope_Status__c, Envelope_Id__c FROM eSignGlobal_Agreement__c WHERE Id = :recordId LIMIT 1];
            
            // Get Access Token
            eSignGlobal_Configuration__c cusSetting = eSignGlobal_Configuration__c.getOrgDefaults();    
            HTTPResponse response1 = ESignGlobalApiCallout.getAccesToken(cusSetting);
            ProcessApiResponseWrapper apiResponseProcess1 = processResponse( response1, recordId , ESignGlobalAgrViewCtrl.GET_ACCES_TOKEN);
            String accessToken = apiResponseProcess1.resultValue;
            
            
            HTTPResponse response2 = ESignGlobalApiCallout.cancelEnvelope(cusSetting, accessToken, eSignGlobal_AgrList[0].Envelope_Id__c, cancelReason );
            ProcessApiResponseWrapper apiResponseProcess2 = processResponse( response2, recordId , CANCEL_ENVELOPE);
            if(apiResponseProcess2.resultValue == 'ENVELOPE_CANCELLED')
            {
                response.responseMsg = SUCCESS;
                eSignGlobal_Agreement__c eSignGlobalAgr = new eSignGlobal_Agreement__c();
                eSignGlobalAgr.Id = eSignGlobal_AgrList[0].Id;
                eSignGlobalAgr.Cancellation_Reason__c = cancelReason;
                eSignGlobalAgr.Error__c = '';
                update eSignGlobalAgr;
            }
                 
            
        }
        catch(Exception Err)
        {
            System.debug(Err.getMessage());
            System.debug(Err.getLineNumber());
            String msg = Err.getMessage();
            System.debug(msg);
            msg = msg.replace('{', '|'); 
            msg = msg.replace('}', '|');
             
            response.responseMsg =  msg;  
            
        }
       
        return response;
    }

      @AuraEnabled
    public static ResponseWrapper resendEnvelope( String recordId )
    {
        ResponseWrapper response = new ResponseWrapper();
        response.responseMsg = SUCCESS;
        try
        {
            System.debug('recordId '+recordId);
            
            List<eSignGlobal_Agreement__c> eSignGlobal_AgrList = new List<eSignGlobal_Agreement__c>();
            eSignGlobal_AgrList = [SELECT Id, Envelope_Status__c, Envelope_Id__c FROM eSignGlobal_Agreement__c WHERE Id = :recordId LIMIT 1];
            
            // Get Access Token
            eSignGlobal_Configuration__c cusSetting = eSignGlobal_Configuration__c.getOrgDefaults();    
            HTTPResponse response1 = ESignGlobalApiCallout.getAccesToken(cusSetting);
            ProcessApiResponseWrapper apiResponseProcess1 = processResponse( response1, recordId , ESignGlobalAgrViewCtrl.GET_ACCES_TOKEN);
            String accessToken = apiResponseProcess1.resultValue;
            
            
            HTTPResponse response2 = ESignGlobalApiCallout.resendEnvelopeCall(cusSetting, accessToken, eSignGlobal_AgrList[0].Envelope_Id__c );
            ProcessApiResponseWrapper apiResponseProcess2 = processResponse( response2, recordId , RESEND_ENVELOPE);
            if(apiResponseProcess2.resultValue == 'ENVELOPE_RESEND')
            {
                response.responseMsg = SUCCESS;
                eSignGlobal_Agreement__c eSignGlobalAgr = new eSignGlobal_Agreement__c();
                eSignGlobalAgr.Id = eSignGlobal_AgrList[0].Id;
                eSignGlobalAgr.Date_Time_of_Resend__c = System.Now();
                update eSignGlobalAgr;
            }
            
                 
            
        }
        catch(Exception Err)
        {
            System.debug(Err.getMessage());
            System.debug(Err.getLineNumber());
            String msg = Err.getMessage();
            System.debug(msg);
            msg = msg.replace('{', '|'); 
            msg = msg.replace('}', '|');
             
            response.responseMsg =  msg;  
            
        }
       
        return response;
    }

    
    public static ProcessApiResponseWrapper processResponse(HTTPResponse res, String recordId, String actionName)
    {

        ProcessApiResponseWrapper apiResponse = New ProcessApiResponseWrapper();
        if(res.getStatusCode() == 200)
        {
            if(actionName == GET_ACCES_TOKEN)
            {
                
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
                apiResponse.resultValue = (String)responseMap.get('access_token');
                apiResponse.callNextApi = true;
            }
            else if(actionName == GET_UPLOAD_URL) 
            {
                Object requestBodyObject = JSON.deserialize(res.getBody(), ESignGlobalAgrViewHelper.FileUploadUrlResponseWrapper.class);
                ESignGlobalAgrViewHelper.FileUploadUrlResponseWrapper uploadUrlDetail = (ESignGlobalAgrViewHelper.FileUploadUrlResponseWrapper) requestBodyObject;
                
                System.debug('uploadUrlDetail ========'+uploadUrlDetail);
                 
                apiResponse.resultValue = uploadUrlDetail.data.fileUploadUrl; 
                apiResponse.fileKey = uploadUrlDetail.data.fileKey;  
                apiResponse.callNextApi = true;
            }
            else if(actionName == UPLOAD_FILE) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
                 
                if( (String)responseMap.get('msg') == '成功' || (String)responseMap.get('msg') == 'success')
                    apiResponse.callNextApi = true;
                else
                {
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    apiResponse.callNextApi = false;
                    throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
                }
                
            }
            else if(actionName == GET_KEYWORD_POSITIONS) 
            {
                system.debug('Get_Keyword_Positions ======== Start');
                Object requestBodyObject = JSON.deserialize(res.getBody(), ESignGlobalAgrViewHelper.KeywordPositionResponseWrapper.class);
                ESignGlobalAgrViewHelper.KeywordPositionResponseWrapper keywordDetail = (ESignGlobalAgrViewHelper.KeywordPositionResponseWrapper) requestBodyObject;
                apiResponse.callNextApi = true;
                System.debug('Get_Keyword_Positions ========'+keywordDetail);
                
                
                List<ESignGlobalAgrViewHelper.KeywordPositionDataWrapper> keywordPositionDataList = keywordDetail.data;
                
                Map<String,List<ESignGlobalAgrViewHelper.SignConfigsWrapper>> signConfigMap = new Map<String,List<ESignGlobalAgrViewHelper.SignConfigsWrapper>>();
                Map<String,List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper>> signDateConfigMap = new Map<String,List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper>>();
                Map<String,List<ESignGlobalAgrViewHelper.FillConfigsWrapper>> fillConfigMap = new Map<String,List<ESignGlobalAgrViewHelper.FillConfigsWrapper>>();
                
                
                System.debug('keywordPositionDataList ========'+keywordPositionDataList);
                if(keywordPositionDataList != null && (!keywordPositionDataList.isEmpty()))
                {
                    for(ESignGlobalAgrViewHelper.KeywordPositionDataWrapper kpdw : keywordPositionDataList)
                    {
                        List<ESignGlobalAgrViewHelper.KeywordPositionWrapper> positions = kpdw.positions;
                        
                        System.debug('positions ========'+positions);
                        if(positions != null && (!positions.isEmpty()))
                        {
                            for(ESignGlobalAgrViewHelper.KeywordPositionWrapper kpw : positions)
                            {
                                List<ESignGlobalAgrViewHelper.KeywordCoordinatesWrapper> coordinates = kpw.coordinates;
                                
                                System.debug('coordinates ========'+coordinates);
                                if(coordinates != null && (!coordinates.isEmpty()))
                                {
                                    for(ESignGlobalAgrViewHelper.KeywordCoordinatesWrapper kcw : coordinates)
                                    {
                                        if( kpdw.keyword == ESignGlobalAgrViewHelper.SIGNER_1_Date )//'{{Dte_es_:signer1:date}}' 
                                        {
                                            ESignGlobalAgrViewHelper.SignDateConfigsWrapper signDateConfig = new ESignGlobalAgrViewHelper.SignDateConfigsWrapper();
                                            signDateConfig.posX = kcw.positionX != NULL ? Decimal.ValueOf(kcw.positionX)-50 : 0;
                                            signDateConfig.posY = kcw.positionY != NULL ? Decimal.ValueOf(kcw.positionY)-5 : 0;
                                            signDateConfig.pageNo = kpw.pageNum;
                                            signDateConfig.signDateFormat = 'dd MMM yyyy';
                                            
                                            if(!signDateConfigMap.containsKey(kpdw.keyword))
                                                signDateConfigMap.put(kpdw.keyword, new List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper>());
                                            signDateConfigMap.get(kpdw.keyword).add(signDateConfig);
                                           
                                        }
                                        else if( kpdw.keyword == ESignGlobalAgrViewHelper.SIGNER_1 || kpdw.keyword == ESignGlobalAgrViewHelper.OF_SIGNER_1 )//legacy or Order Form v1.2 signature tag
                                        {
                                            ESignGlobalAgrViewHelper.SignConfigsWrapper signConfig = new ESignGlobalAgrViewHelper.SignConfigsWrapper();
                                            signConfig.posX = kcw.positionX != NULL ? Decimal.ValueOf(kcw.positionX)-60 : 0;//30
                                            signConfig.posY = kcw.positionY != NULL ? Decimal.ValueOf(kcw.positionY)-10 : 0;
                                            signConfig.pageNo = kpw.pageNum;
                                            signConfig.fieldType = 'signature';
                                            signConfig.addSignDate = true;

                                            // key normalised to SIGNER_1 so both tag generations feed the same config list
                                            if(!signConfigMap.containsKey(ESignGlobalAgrViewHelper.SIGNER_1))
                                                signConfigMap.put(ESignGlobalAgrViewHelper.SIGNER_1, new List<ESignGlobalAgrViewHelper.SignConfigsWrapper>());
                                            signConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1).add(signConfig);
                                        }
                                        else if( kpdw.keyword == ESignGlobalAgrViewHelper.SIGNER_1_Name || kpdw.keyword == ESignGlobalAgrViewHelper.OF_SIGNER_1_Name )
                                        {
                                            ESignGlobalAgrViewHelper.FillConfigsWrapper fillConfig = new ESignGlobalAgrViewHelper.FillConfigsWrapper();
                                            fillConfig.posX = kcw.positionX != NULL ? Decimal.ValueOf(kcw.positionX)-50 : 0;
                                            fillConfig.posY = kcw.positionY != NULL ? Decimal.ValueOf(kcw.positionY)-5 : 0;
                                            fillConfig.pageNo = kpw.pageNum;
                                            fillConfig.fieldType = '1';
                                            fillConfig.fieldId = 'Signer1Name';
                                            fillConfig.fieldKey = 'Signer1Name';
                                            fillConfig.fieldName = 'Signer Name';
                                            fillConfig.required = true;

                                            // key normalised to SIGNER_1_Name so both tag generations feed the same fill list
                                            if(!fillConfigMap.containsKey(ESignGlobalAgrViewHelper.SIGNER_1_Name))
                                                fillConfigMap.put(ESignGlobalAgrViewHelper.SIGNER_1_Name, new List<ESignGlobalAgrViewHelper.FillConfigsWrapper>());
                                            fillConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1_Name).add(fillConfig);

                                        }
                                        else if( kpdw.keyword == ESignGlobalAgrViewHelper.OF_SIGNER_1_Title )
                                        {
                                            // Order Form v1.2 Position/title line - filled by the signer like the name
                                            ESignGlobalAgrViewHelper.FillConfigsWrapper fillConfig = new ESignGlobalAgrViewHelper.FillConfigsWrapper();
                                            fillConfig.posX = kcw.positionX != NULL ? Decimal.ValueOf(kcw.positionX)-50 : 0;
                                            fillConfig.posY = kcw.positionY != NULL ? Decimal.ValueOf(kcw.positionY)-5 : 0;
                                            fillConfig.pageNo = kpw.pageNum;
                                            fillConfig.fieldType = '1';
                                            fillConfig.fieldId = 'Signer1Title';
                                            fillConfig.fieldKey = 'Signer1Title';
                                            fillConfig.fieldName = 'Signer Title';
                                            fillConfig.required = true;

                                            if(!fillConfigMap.containsKey(ESignGlobalAgrViewHelper.SIGNER_1_Name))
                                                fillConfigMap.put(ESignGlobalAgrViewHelper.SIGNER_1_Name, new List<ESignGlobalAgrViewHelper.FillConfigsWrapper>());
                                            fillConfigMap.get(ESignGlobalAgrViewHelper.SIGNER_1_Name).add(fillConfig);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                apiResponse.signConfigMap = signConfigMap;
                apiResponse.signDateConfigMap = signDateConfigMap;
                apiResponse.fillConfigMap = fillConfigMap;
            }
            else if(actionName == CREATE_ENVELOPE) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
                Map<String,Object> dataObj = (Map<String,Object>)responseMap.get('data');
                apiResponse.resultValue = (String)dataObj.get('envelopeId');
                apiResponse.callNextApi = true;
            }
            else if(actionName == ADD_FILE_TO_ENVELOPE) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
                if( (String)responseMap.get('message') == 'success')
                    apiResponse.callNextApi = true;
                else
                {
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    apiResponse.callNextApi = false;
                    throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
                }
            }
            else if(actionName == ADD_SIGNER) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody()); 
                if( (String)responseMap.get('message') == 'success')
                    apiResponse.callNextApi = true;
                else
                {
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    apiResponse.callNextApi = false;
                    throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
                }
            }
            else if(actionName == ENVELOPE_SENDER_VIEW) 
            {
                
                Object requestBodyObject = JSON.deserialize(res.getBody(), ESignGlobalAgrViewHelper.EnvelopeSenderViewResponseWrapper.class);
                ESignGlobalAgrViewHelper.EnvelopeSenderViewResponseWrapper envelopeSenderViewDetail = (ESignGlobalAgrViewHelper.EnvelopeSenderViewResponseWrapper) requestBodyObject;
                
                if( envelopeSenderViewDetail.message  == 'success' )
                {
                    apiResponse.callNextApi = true;
                    apiResponse.resultValue = envelopeSenderViewDetail.data.url;
                }
                else
                {
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    apiResponse.callNextApi = false;
                    throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
                }
            }
            else if(actionName == CANCEL_ENVELOPE) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody()); 
                if( (String)responseMap.get('message') == 'success')
                    apiResponse.resultValue = 'ENVELOPE_CANCELLED';
                else
                {
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    apiResponse.callNextApi = false;
                    throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
                }
            }
            else if(actionName == RESEND_ENVELOPE) 
            {
                Map<String,Object> responseMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody()); 
                if( (String)responseMap.get('message') == 'success')
                    apiResponse.resultValue = 'ENVELOPE_RESEND';
                else
                {
                    /*
                    eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                    eSign.Id = recordId;
                    eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
                    update eSign; 
                    */
                    throw new Ast_CustomException( res.getBody() );
                }
            }
            
            
        }
        else
        {
            eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
            eSign.Id = recordId;
            eSign.Error__c = 'Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
            update eSign; 
            
            apiResponse.callNextApi = false;
            
            throw new Ast_CustomException( res.getBody() + ' Error : '+ actionName + ' | '+ 'Status Code : '+res.getStatusCode() );
        }
        
        return apiResponse;
        /*         
try
{}
catch(Exception Err)
{
System.debug(Err.getMessage());
System.debug(Err.getLineNumber());

eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
eSign.Id = recordId;
eSign.Error__c = 'Status Code : '+res.getStatusCode() + ' | '+ 'Response Body : '+res.getBody();
update eSign;

throw new Ast_CustomException( Err.getMessage() + ' | Error Line : '+ Err.getLineNumber() );

}
*/
        
    }
    
    public class ProcessApiResponseWrapper
    {
        @AuraEnabled public Boolean callNextApi {get;Set;}
        @AuraEnabled public String resultValue {get;Set;}
        @AuraEnabled public String fileKey {get;Set;}
        
        @AuraEnabled public Map<String,List<ESignGlobalAgrViewHelper.SignConfigsWrapper>> signConfigMap {get;Set;}
        @AuraEnabled public Map<String,List<ESignGlobalAgrViewHelper.SignDateConfigsWrapper>> signDateConfigMap {get;Set;}
        @AuraEnabled public Map<String,List<ESignGlobalAgrViewHelper.FillConfigsWrapper>> fillConfigMap {get;Set;}
    }
    
    
    
    
    
    
}