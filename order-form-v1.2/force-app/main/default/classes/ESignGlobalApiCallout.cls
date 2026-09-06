public class ESignGlobalApiCallout {
    
    // Method to fetch access token.
    public static HTTPResponse getAccesToken(eSignGlobal_Configuration__c cusSetting)
    {
        String endpoint = cusSetting.Base_endpoint_Url__c + '/esignglobal/v1/oauth2/accessToken';
        
        // Create map of parameters
        Map<String, String> params = new Map<String, String>{
            'grant_type' => 'client_credentials',
                'client_id' => cusSetting.Client_Id__c,
                'client_secret' => cusSetting.Client_Secret__c
                };
                    // Add parameters to endpoint
                    endpoint += '?' + getQueryString(params);
        
        // Create and send HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        
        return res;
        
    }
    
    private static String getQueryString(Map<String, String> params) {
        List<String> keyValuePairs = new List<String>();
        for (String key : params.keySet()) {
            keyValuePairs.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + 
                              EncodingUtil.urlEncode(params.get(key), 'UTF-8'));
        }
        return String.join(keyValuePairs, '&');
    }
    
    
    
    
    //   Method to Upload Document.
    public static HTTPResponse getFileUploadUrl(eSignGlobal_Configuration__c cusSetting, String accessToken, eSignGlobal_Agreement__c eSignGlobal_Agr)
    {
        
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/files/getUploadUrl';
        
        // Create and send HTTP request
        System.debug(endpoint);
        //String fileData = generatePDF( eSignGlobal_Agr.Id );
        
        String jsonData = ' {'+ '"fileName": "'+eSignGlobal_Agr.Quote_Document__r.Name+'.pdf" '+ ' }';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        System.debug(jsonData);
        // Process response
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        
        return res;
        // Sample response - {"code":"0","data":{"signFiles":[{"fileKey":"$0508d527-d114-4677-aac7-6bdd8e18a59b$646698825"}],"envelopeId":"eff9a3a3db2141c08f3449bc7072c8cd"},"message":"success"}
    }
    
    /*
public static String generatePDF(String eSignGlobalAgrId) 
{

List<ContentDocumentLink> contentDocLink = new List<ContentDocumentLink>();
contentDocLink = [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :eSignGlobalAgrId LIMIT 1];

// Query the ContentVersion record
ContentVersion cv = [SELECT Id, VersionData FROM ContentVersion WHERE ContentDocumentId  = :contentDocLink[0].ContentDocumentId LIMIT 1];

Blob pdfBlob = cv.VersionData;

Blob md5Hash = Crypto.generateDigest('MD5', pdfBlob);

String contentMd5 = EncodingUtil.base64Encode(md5Hash);

return contentMd5;
}
*/
    
    
    public static HTTPResponse uploadDocToUrl( String fileUploadUrl, String accessToken, eSignGlobal_Agreement__c eSignGlobal_Agr)
    {
        
        System.debug('fileUploadUrl = '+fileUploadUrl);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(fileUploadUrl);
        req.setMethod('PUT');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        
        req.setBodyAsBlob(generatePDF(eSignGlobal_Agr.Id) );
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res;
        
    }
    
    public static Blob generatePDF(String eSignGlobalAgrId) 
    {
        
        List<ContentDocumentLink> contentDocLink = new List<ContentDocumentLink>();
        contentDocLink = [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :eSignGlobalAgrId LIMIT 1];
        
        // Query the ContentVersion record
        ContentVersion cv = [SELECT Id, VersionData FROM ContentVersion WHERE ContentDocumentId  = :contentDocLink[0].ContentDocumentId LIMIT 1];
        
        return cv.VersionData;
    }
    
    public static HTTPResponse getkeywordPositions(eSignGlobal_Configuration__c cusSetting, String accessToken, String fileKey)
    {
        
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/files/keywordPositions';
        
        Set<String> signerSet = new Set<String>();
        signerSet.add(ESignGlobalAgrViewHelper.SIGNER_1);
        signerSet.add(ESignGlobalAgrViewHelper.SIGNER_1_Date);
        signerSet.add(ESignGlobalAgrViewHelper.SIGNER_1_Name);
        // Order Form v1.2 tag variants (see helper) - searched alongside the legacy keywords
        signerSet.add(ESignGlobalAgrViewHelper.OF_SIGNER_1);
        signerSet.add(ESignGlobalAgrViewHelper.OF_SIGNER_1_Name);
        signerSet.add(ESignGlobalAgrViewHelper.OF_SIGNER_1_Title);
        
        String signerSetString = JSON.serialize(signerSet);
        System.debug(signerSetString);
        
        String jsonData = '{"fileKey": "'+fileKey+'", "keywords": '+ signerSetString +'} ';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res; 
    }
    
    
    public static HTTPResponse createEnvelope(eSignGlobal_Configuration__c cusSetting, String accessToken, eSignGlobal_Agreement__c eSignGlobal_Agr,
                                              String subject)
    {
        String baseURL = cusSetting.Base_endpoint_Url__c;
        String endpoint = baseURL+'/esignglobal/v1/envelope/create';
        
        // Create map of parameters
        Map<String, String> params = new Map<String, String>{
            'subject' => eSignGlobal_Agr.Quote_Document__r.Name
                };
                    // Create and send HTTP request
                    System.debug(endpoint);
        
        String jsonData = '{  "subject": "'+subject+'"} ';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        // Process response
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res;
    }
    
    public static HTTPResponse cancelEnvelope(eSignGlobal_Configuration__c cusSetting, String accessToken, String envelopeId, String reason )
    {
        String baseURL = cusSetting.Base_endpoint_Url__c;
        String endpoint = baseURL+'/esignglobal/v1/envelope/cancel';
        
        // Create map of parameters
        /*Map<String, String> params = new Map<String, String>{
            'envelopeId' => envelopeId,
                'reason' => reason
                };*/
                    // Create and send HTTP request
                    System.debug(endpoint);
        
        String jsonData = '{  "envelopeId": "'+envelopeId+'" ,"reason": "'+reason+'"  } ';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        // Process response
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res;
    }
    
    
    
    public static HTTPResponse addDocuments(eSignGlobal_Configuration__c cusSetting , String accessToken, String fileKey, String envelopeId)
    {
        
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/envelope/files/addSignFiles';
        // Create and send HTTP request
        System.debug(endpoint);
        
        
        String jsonData = ' {"envelopeId": "'+envelopeId+'","signFiles":'+
            ' [{"fileKey": "'+fileKey+'"}]}';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        
        return res;
        
    }
    
    
    public static HTTPResponse addSignatories( eSignGlobal_Configuration__c cusSetting , String accessToken, ESignGlobalAgrViewHelper.SignerRequestWrapper SignerDetail  )
    {
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/envelope/recipients/addSigners';
        System.debug(endpoint);
        
        String jsonData = JSON.serialize(SignerDetail);  
         
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        System.debug(jsonData);
        
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res;
    }
    
    
    public static HTTPResponse envelopeSenderView(eSignGlobal_Configuration__c cusSetting , String accessToken, String envelopeId,String returnUrl)
    {
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/envelopes/views/sender';
        
        String jsonData = '{  '+
            '"envelopeId": "'+envelopeId+'", '+  
            '"returnUrl":"'+returnUrl+'"'+
            '} ';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        // Process response
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        
        return res;
    }
    
    
         
    public static HTTPResponse downloadSignedDocuments(eSignGlobal_Configuration__c cusSetting , String accessToken, String envelopeId)
    {
       
        String endpoint = cusSetting.Base_endpoint_Url__c+'/esignglobal/v1/envelope/files/download';
        
        // Create map of parameters
        Map<String, String> params = new Map<String, String>{
            'envelopeId' => envelopeId
                };
                    // Add parameters to endpoint
                    endpoint += '?' + getQueryString(params);
         
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        // Process response
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res; 
    }
   
    
    public static void downloadAndSaveFile(String fileDownloadUrl, String recordId, String oppId)
    {
         
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(fileDownloadUrl);
        request.setMethod('GET');
        HttpResponse response = http.send(request);
        System.debug('response '+response);
        
        if(response.getStatusCode() == 200) {
            Blob fileBody = response.getBodyAsBlob();
            
            /*  Below commented code is to save zip file in salesforce
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Downloaded File';
            cv.PathOnClient = 'file.zip';
            cv.VersionData = fileBody; // Blob from the HTTP response
            insert cv;
            
            ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = insertedCv.ContentDocumentId;
            cdl.LinkedEntityId = recordId; // e.g., Account, Case, etc.
            cdl.ShareType = 'V'; // Viewer permission
            cdl.Visibility = 'AllUsers';
            insert cdl;
            */
            
            // Instantiate the ZipReader with the downloaded blob
            Compression.ZipReader reader = new Compression.ZipReader(fileBody);
             
            List<ContentDocumentLink> contentDocumentLinkList = new List<ContentDocumentLink>();
            
            Boolean setErrorFieldNull = false;
            // Iterate through the entries in the ZIP file
            for (Compression.ZipEntry entry : reader.getEntries()) 
            {
                
                String fileName = entry.getName();
                Blob fileContent = entry.getContent();
                System.debug('fileName '+fileName);
                
                if(fileName.contains('.pdf'))
                {
                    ContentVersion cv1 = new ContentVersion();
                    cv1.Title = 'Signed_'+(fileName.contains('/') ? fileName.substringAfterLast('/') : fileName);                  //name+'.pdf';
                    cv1.PathOnClient = 'Signed_'+(fileName.contains('/') ? fileName.substringAfterLast('/') : fileName); 
                    cv1.VersionData = fileContent; // Blob from the HTTP response
                    cv1.FirstPublishLocationId = recordId;   
                    insert cv1;
                    
                    ContentVersion insertedCv1 = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv1.Id];
                    /*
                    ContentDocumentLink cdl1 = new ContentDocumentLink();
                    cdl1.ContentDocumentId = insertedCv1.ContentDocumentId;
                    cdl1.LinkedEntityId = recordId; // e.g., Account, Case, etc.
                    cdl1.ShareType = 'V'; // Viewer permission
                    cdl1.Visibility = 'AllUsers';
                    */
                    
                    ContentDocumentLink cdl2 = new ContentDocumentLink();
                    cdl2.ContentDocumentId = insertedCv1.ContentDocumentId;
                    cdl2.LinkedEntityId = oppId; // e.g., Account, Case, etc.
                    cdl2.ShareType = 'V'; // Viewer permission
                    cdl2.Visibility = 'AllUsers';
                    
                    
                    //contentDocumentLinkList.add(cdl1);
                    contentDocumentLinkList.add(cdl2);
                    
                    setErrorFieldNull = true;
                    
                }
            }
            
            if(contentDocumentLinkList.size() > 0)
                insert contentDocumentLinkList;
            
            if(setErrorFieldNull)
            {
                eSignGlobal_Agreement__c eSign = new eSignGlobal_Agreement__c();
                eSign.Id = recordId;
                eSign.Error__c = null;
                update eSign;
            }
            // reader.close();
            
            
            
        }
        
    }
    
    public static HTTPResponse resendEnvelopeCall(eSignGlobal_Configuration__c cusSetting, String accessToken, String envelopeId)
    {
        String baseURL = cusSetting.Base_endpoint_Url__c;
        String endpoint = baseURL+'/esignglobal/v1/envelope/urge';
        
        
        // Create and send HTTP request
        System.debug(endpoint);
        
        String jsonData = '{  "envelopeId": "'+envelopeId+'"} ';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        String authorizationHeader = 'Bearer ' + accessToken;
        req.setHeader('Authorization', authorizationHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonData);
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        
        // Process response
        System.debug('resendEnvelopeCall======'); 
        System.debug(res.getStatusCode());
        System.debug(res.getBody());
        return res;
    }
    
    
    
    
    
    
    
}