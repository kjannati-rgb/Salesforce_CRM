public class ESignGlobalAgrViewHelper {
    
    public static Final String SIGNER_1 = '{{Sig_es_:signer1:signature}}'; //'{{ESG_Signer_1}}';
    public static Final String SIGNER_1_Date = '{{Dte_es_:signer1:date}}'; //'{{ESG_SignerDate_1}}';
    public static Final String SIGNER_1_Name = '{{*Name1_es_:fullname}}';
    // Order Form v1.2 (Subscription Order Form template) tag variants - Aug 2026.
    // The Order Form uses Adobe-required-field tags; these are searched IN ADDITION to the
    // legacy keywords above so both template generations anchor correctly. Date tag is shared.
    public static Final String OF_SIGNER_1 = '{{*Sig_es_:signer1:signature}}';
    public static Final String OF_SIGNER_1_Name = '{{N_es_:signer1:fullname}}';
    public static Final String OF_SIGNER_1_Title = '{{*Ttl_es_:signer1:title}}';
    public static Final Map<String,String> STATUS_CODE_MAP = new Map<String,String>{ '0'=> 'Draft','1'=> 'In Progress','2'=> 'Completed','3'=> 'Expired','5'=> 'Canceled'};
    public static Final Map<String,String> EVENT_TYPE_DESCRIPTION_MAP = new Map<String,String>{ 'ENVELOPE_START'=> 'Envelope Open Notification','ENVELOPE_SIGNER_SIGNED'=> 'Signatory Signed Completion Notice','ENVELOPE_ALL_SIGNER_SIGNED'=> 'Completion notice signed by all signatories','ENVELOPE_FINISH'=> 'Envelope End Notice','ENVELOPE_CANCEL'=> 'Notice of Revocation of Envelope','ENVELOPE_EXPIRED' => 'Notice of Envelope Expiration'};
    public static Final Map<String,String> SIGNER_STATUS_CODE_MAP = new Map<String,String>{ '1' => 'Pending to Sign', '2' => 'Signed'};
        
    public class FileUploadUrlResponseWrapper
    {
        
        @AuraEnabled public String code {get;Set;}
        @AuraEnabled public FileUploadUrlDataWrapper data {get;Set;}
    }
    
    public class FileUploadUrlDataWrapper                  
    {
        @AuraEnabled public String fileUploadUrl {get;Set;}
        @AuraEnabled public String fileName {get;Set;}
        @AuraEnabled public String fileKey {get;Set;}
    }
    
    //---------------------------------------------------------
    
    
    public class KeywordPositionResponseWrapper
    {
        
        @AuraEnabled public String code {get;Set;}
        @AuraEnabled public List<KeywordPositionDataWrapper> data {get;Set;}
    }
    
    public class KeywordPositionDataWrapper
    {
        @AuraEnabled public String keyword {get;Set;}
        @AuraEnabled public List<KeywordPositionWrapper> positions {get;Set;}
        @AuraEnabled public Boolean searchResult {get;Set;}
    }
    
    public class KeywordPositionWrapper
    {
        @AuraEnabled public String pageNum {get;Set;}
        @AuraEnabled public List<KeywordCoordinatesWrapper> coordinates {get;Set;}
        
    }
    
    public class KeywordCoordinatesWrapper
    {
        @AuraEnabled public String positionX {get;Set;}
        @AuraEnabled public String positionY {get;Set;}
    }
    
    //--------------------------------------------------------------------------------
    
    
    public class SignerRequestWrapper
    {
        @AuraEnabled public String envelopeId {get;Set;}
        @AuraEnabled public List<SignerInfoWrapper> signerInfos {get;Set;}
    }
    
    public class SignerInfoWrapper
    {
        @AuraEnabled public String userEmail {get;Set;}
        @AuraEnabled public String userName {get;Set;}
        @AuraEnabled public Integer signOrder {get;Set;}
        @AuraEnabled public String authModes {get;Set;}
        @AuraEnabled public List<SealInfosWrapper> sealInfos {get;Set;}
    }
    
    public class SealInfosWrapper
    {
        @AuraEnabled public String fileKey {get;Set;}
        @AuraEnabled public List<SignConfigsWrapper> signConfigs {get;Set;}
        @AuraEnabled public List<SignDateConfigsWrapper> signDateConfigs {get;Set;}
        @AuraEnabled public List<FillConfigsWrapper> fillConfigs {get;Set;}
    }
    
    
    public class SignConfigsWrapper
    {
        @AuraEnabled public String fieldType {get;Set;}
        @AuraEnabled public String pageNo {get;Set;}
        @AuraEnabled public Decimal posX {get;Set;}
        @AuraEnabled public Decimal posY {get;Set;}
        @AuraEnabled public Boolean addSignDate {get;Set;}
    }
    
    public class SignDateConfigsWrapper
    {
        
        @AuraEnabled public String pageNo {get;Set;}
        @AuraEnabled public Decimal posX {get;Set;}
        @AuraEnabled public Decimal posY {get;Set;}
        @AuraEnabled public String signDateFormat {get;Set;}
    }
    
    public class FillConfigsWrapper
    {
        
        @AuraEnabled public String fieldName {get;Set;}
        @AuraEnabled public String fieldId {get;Set;}
        @AuraEnabled public String fieldKey {get;Set;}
        @AuraEnabled public String pageNo {get;Set;}
        @AuraEnabled public Decimal posX {get;Set;}
        @AuraEnabled public Decimal posY {get;Set;}
        @AuraEnabled public String fieldType {get;Set;}
        @AuraEnabled public Boolean required {get;Set;}
    }
    
    
    // ----------------
    
    public class EnvelopeSenderViewResponseWrapper
    {
        @AuraEnabled public String code {get;Set;}
        @AuraEnabled public String message {get;Set;}
        @AuraEnabled public EnvelopeSenderViewDataResponseWrapper data {get;Set;}
    }   
    
    public class EnvelopeSenderViewDataResponseWrapper
    {
        @AuraEnabled public String url {get;Set;}
    }   
    
    //--------------------------
    
    public class EnvelopeStatusWrapper
    {
        @AuraEnabled public String event {get;Set;}
        @AuraEnabled public EventPayloadWrapper eventPayload {get;Set;}
    }   
    
     public class EventPayloadWrapper
    {
        @AuraEnabled public String envelopeId {get;Set;}
        /*
            Envelope Status :
            0-Draft
            1-In Progress
            2-Completed
            3-Expired
            5-Canceled         
        */
        @AuraEnabled public String envelopeStatus {get;Set;} 
        @AuraEnabled public String envelopeStartTime {get;Set;}
        @AuraEnabled public String expireTime {get;Set;}
        @AuraEnabled public List<EventPayloadSignerWrapper> signerList {get;Set;}
        @AuraEnabled public EventPayloadSignerWrapper signerInfo {get;Set;}
    }   
    
     public class EventPayloadSignerWrapper
    {
        @AuraEnabled public String userEmail {get;Set;}
        @AuraEnabled public String userName {get;Set;}
        @AuraEnabled public String signOrder {get;Set;}
        @AuraEnabled public String signerStatus {get;Set;}  // 0-Pending to Sign ; 1-Signed
        @AuraEnabled public String authModes {get;Set;}
    } 
    
    public static List<ESignGlobalAgrViewHelper.SignConfigsWrapper> defaultSignerBlockPosition()
    {
        List<ESignGlobalAgrViewHelper.SignConfigsWrapper> signConfigList = new List<ESignGlobalAgrViewHelper.SignConfigsWrapper>();
        ESignGlobalAgrViewHelper.SignConfigsWrapper signConfig = new ESignGlobalAgrViewHelper.SignConfigsWrapper();
        signConfig.posX = 20;
        signConfig.posY = 20;
        signConfig.pageNo = '1';
        signConfig.fieldType = 'signature';
        signConfig.addSignDate = false;
        signConfigList.add(signConfig);
        return signConfigList;
    }
    
    
    
}