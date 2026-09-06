public class RenewalOpportunityHandler2 {

    public static Map<Id,Integer> OpportunityTermByOppId = new Map<Id,Integer>();
    public static Map<Id, Product2> existingRenewalProductByPreviousProductId = new Map<Id, Product2>();
    public static Map<Id, Product2> existingNdNewlyCreatedRenewalProductByPreviousOPId = new Map<Id, Product2>();
    public static Map<String, String> mm = new Map<String, String>();
    //variables to create records
    public static Map<Id, Opportunity> renewalOppByPreviousOppId; // Renewal Opportunities
    public static Map<Id, SBQQ__Quote__c> renewalPrimaryQuotesByPreviousQId; // Renewal Quotes
    public static List<SBQQ__QuoteLine__c> renewalOppsQuoteLinesToCreate =new List<SBQQ__QuoteLine__c>() ; //Renewal Quotes Lines
  
    /***************************************Maps Created By Kriti On October 8***********************************************/
    public static Map<SBQQ__QuoteLine__c,String> productNameWithoutYearByQuoteline=new Map<SBQQ__QuoteLine__c,String>() ;
    public static Map<SBQQ__QuoteLine__c,Integer> editionYearByQuoteline=new Map<SBQQ__QuoteLine__c,Integer>() ;
    public static Map<String,SBQQ__QuoteLine__c> quotelineByproductNameWithoutYear=new Map<String,SBQQ__QuoteLine__c>() ;
    /***************************************Maps Created By Kriti On October 8***********************************************/

    /**
     * Inserts recordsByKey with partial success (allOrNone = false) so one failing record
     * does not roll back or block the rest of the batch (fixes D3 - a downstream flow fault,
     * a restricted picklist value, or a row lock on one record used to take down every
     * renewal in the transaction). Failed records are logged to Flow_Log__c and removed from
     * recordsByKey so later steps do not reference a record that was never created.
     *
     * @param recordsByKey records to insert, keyed by whatever id the caller needs to look
     *        them up by afterwards (the previous year's product/record id in every caller here)
     * @param stepLabel short label identifying which creation step this is, for the log
     */
    private static void insertPartial(Map<Id, SObject> recordsByKey, String stepLabel) {
        if (recordsByKey.isEmpty()) {
            return;
        }
        List<Id> keys = new List<Id>(recordsByKey.keySet());
        List<SObject> records = recordsByKey.values();
        List<Database.SaveResult> results = Database.insert(records, false);
        List<Flow_Log__c> failureLogs = new List<Flow_Log__c>();
        Id apexLogRecordTypeId = Schema.SObjectType.Flow_Log__c.getRecordTypeInfosByDeveloperName().get('Apex_Error').getRecordTypeId();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Id failedKey = keys[i];
                recordsByKey.remove(failedKey);
                String errorText = '';
                for (Database.Error err : results[i].getErrors()) {
                    errorText += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                Flow_Log__c errorLog = new Flow_Log__c();
                errorLog.Class_Name__c = 'RenewalOpportunityHandler2';
                errorLog.Error_Description__c = stepLabel + ' failed for previous record ' + failedKey + ' - ' + errorText;
                errorLog.Record_Name__c = 'RecordId: ' + failedKey;
                errorLog.recordtypeid = apexLogRecordTypeId;
                failureLogs.add(errorLog);
            }
        }
        if (!failureLogs.isEmpty()) {
            insert failureLogs;
        }
    }

    /**
     * Inserts records with partial success (allOrNone = false), logging any failures to
     * Flow_Log__c without rolling back the rest of the batch. Use this overload for plain
     * lists that have no natural previous-record key to prune by; use insertPartial(Map,
     * String) when downstream steps need failed records removed from a lookup map.
     */
    private static void insertPartialList(List<SObject> records, String stepLabel) {
        if (records.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.insert(records, false);
        List<Flow_Log__c> failureLogs = new List<Flow_Log__c>();
        Id apexLogRecordTypeId = Schema.SObjectType.Flow_Log__c.getRecordTypeInfosByDeveloperName().get('Apex_Error').getRecordTypeId();
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                String errorText = '';
                for (Database.Error err : result.getErrors()) {
                    errorText += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                Flow_Log__c errorLog = new Flow_Log__c();
                errorLog.Class_Name__c = 'RenewalOpportunityHandler2';
                errorLog.Error_Description__c = stepLabel + ' failed - ' + errorText;
                errorLog.Record_Name__c = stepLabel;
                errorLog.recordtypeid = apexLogRecordTypeId;
                failureLogs.add(errorLog);
            }
        }
        if (!failureLogs.isEmpty()) {
            insert failureLogs;
        }
    }

    /**
     * Clones the previous year's Opportunity/Quote/QuoteLines into a renewal Opportunity
     * for each activated order line that is renewal-eligible. Called from
     * RenewalOpportunityQueueable, not directly from the trigger - queueable so it can be
     * enqueued once per trigger invocation (chunk-safe) instead of relying on a static
     * runOnce guard.
     */
    public static void processOpportunities(Map<Id, Id> OwnerIdBYoppoId,Map<Id, Id> OrderIdBYoppoId){
       
        Map<Id, Product2> renewalProductsByPreviousProductId; //Renewal Products
        Map<Id, Product2> renewalOptionalProductsByPreviousOPId ; //Renewal Optional Products
        Map<Id, SBQQ__ProductFeature__c> renewProductFeaturesPreviousPFIds; //Renewal Product Features
        List<PriceBookEntry> priceBookEntriesToBeCreated;  // Renewal Pricebooks
        Map<Id, SBQQ__ProductOption__c> renewalProductOptionsByPreviousId;
        Map<Id, SBQQ__ConfigurationRule__c> renewalConfigRuleByPreConfigRuleId;
        Set<Id> renewalNotRequiredForOppIds = new Set<Id>();
        Savepoint sp = Database.setSavepoint(); 
        List<SBQQ__QuoteLine__c> previousOppsQuoteLines= new List<SBQQ__QuoteLine__c>([
            SELECT Id,Name,SBQQ__Quote__c,SBQQ__Quote__r.SBQQ__Opportunity2__c,SBQQ__Quote__r.SBQQ__PriceBook__c,SBQQ__Quote__r.CurrencyIsoCode,SBQQ__ListPrice__c,SBQQ__Bundled__c,  
            SBQQ__StartDate__c,SBQQ__EndDate__c, SBQQ__NetPrice__c,SBQQ__Quantity__c,SBQQ__PriceEditable__c,SBQQ__PricingMethodEditable__c,
            SBQQ__SpecialPrice__c,SBQQ__RegularPrice__c,SBQQ__PricebookEntryId__c,SBQQ__ProratedListPrice__c,SBQQ__ProratedPrice__c,SBQQ__UnproratedNetPrice__c,SBQQ__MarkupAmount__c,SBQQ__MarkupRate__c,
            Finance_Code_for_SUN__c,SBQQ__Discount__c,SBQQ__CustomerPrice__c,Financial_Year__c,Finance_Code__c,SBQQ__SubscriptionType__c,Subscription_Model__c,SBQQ__ProductSubscriptionType__c,SBQQ__AdditionalDiscountAmount__c,
            CurrencyIsoCode,SBQQ__PriorQuantity__c,SBQQ__Existing__c,SBQQ__Renewal__c,SBQQ__SubscriptionPricing__c,SBQQ__AllowAssetRefund__c,SBQQ__UpgradedQuantity__c,
            SBQQ__CarryoverLine__c,SBQQ__PricingMethod__c,SBQQ__DiscountScheduleType__c,Adobe_Sign_Content_Slot_Title__c,Content_Slot__c,
            ContentSlotsForBundleProduct__c,SBQQ__Number__c,Brand__c,Content_Type__c,Feature_Name__c,Pricing_Band__c,SBQQ__ProductOption__c, SBQQ__ProductOption__r.SBQQ__ConfiguredSKU__c,
            SBQQ__Product__r.Name,SBQQ__Product__r.Reporting_Stream__c,SBQQ__Product__r.Division__c,SBQQ__Product__r.Family,
            SBQQ__Product__r.Subscription_Model__c,SBQQ__Product__r.Financial_Year__c,
            SBQQ__Product__r.Product_Budget_Date__c,SBQQ__Product__r.Edition__c,SBQQ__Product__r.Product_Date__c,SBQQ__Product__r.Id,SBQQ__Product__r.CanUseRevenueSchedule,SBQQ__Product__r.ProductCode,
            SBQQ__Product__r.SBQQ__PricingMethodEditable__c,SBQQ__Product__r.SBQQ__PriceEditable__c,SBQQ__Product__r.Bundle__c,
            SBQQ__Product__r.SBQQ__Hidden__c,SBQQ__Product__r.SBQQ__ExcludeFromOpportunity__c,
            SBQQ__Product__r.Publication__c,SBQQ__Product__r.SBQQ__ConfigurationEvent__c,SBQQ__Product__r.SBQQ__ConfigurationType__c,SBQQ__Product__r.Revenue_Stream__c,SBQQ__Product__r.Brand__c,
            SBQQ__Product__r.Product_Type__c,SBQQ__Product__r.Product_Type_2__c,SBQQ__Product__r.Product_Type_3__c,
            SBQQ__Product__r.Reporting_Group__c,SBQQ__Product__r.Event_Title_Edition__c,SBQQ__Product__r.Event__c ,SBQQ__Product__r.SBQQ__SubscriptionTerm__c,SBQQ__Product__r.SBQQ__SubscriptionType__c,SBQQ__Product__r.Publication_Title__c,
            SBQQ__Product__r.Event_Location_Country__c,SBQQ__Product__r.SBQQ__QuantityEditable__c,SBQQ__Product__r.SBQQ__AssetConversion__c,	
            SBQQ__Product__r.SBQQ__OptionLayout__c,SBQQ__Product__r.SBQQ__HidePriceInSearchResults__c,SBQQ__Product__r.Default_Tax_Code__c,
            SBQQ__Product__r.Team__c,SBQQ__Product__r.Date_Logic_Group__c,SBQQ__Product__r.SBQQ__Component__c,SBQQ__Product__r.Content_Slot_Required__c,
            SBQQ__Product__r.Renewal_Not_Required__c,SBQQ__Product__r.SBQQ__RenewalProduct__c,SBQQ__Product__r.SBQQ__RenewalProduct__r.Name FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__r.SBQQ__Opportunity2__c IN: OwnerIdBYoppoId.keyset() AND SBQQ__Quote__r.SBQQ__Primary__c = true
        ]); //Previous Quotelines with Products
        List<Integer> ProductsFinancialYear =new List<Integer>();

        /*
         * Eligibility is evaluated per line, not per opportunity (fixes D2). An opportunity
         * only goes into renewalNotRequiredForOppIds when NONE of its primary-quote lines are
         * renewal-eligible - one flagged product must not block the rest of the deal.
         */
        Set<Id> oppIdsWithEligibleLine = new Set<Id>();
        Set<Id> oppIdsWithAnyLine = new Set<Id>();
        for(SBQQ__QuoteLine__c pQLines: previousOppsQuoteLines) {
            Id oppId = pQLines.SBQQ__Quote__r.SBQQ__Opportunity2__c;
            oppIdsWithAnyLine.add(oppId);
            if (!pQLines.SBQQ__Product__r.Renewal_Not_Required__c) {
                oppIdsWithEligibleLine.add(oppId);
            }
        }
        for (Id oppId : oppIdsWithAnyLine) {
            if (!oppIdsWithEligibleLine.contains(oppId)) {
                renewalNotRequiredForOppIds.add(oppId);
            }
        }

        for(SBQQ__QuoteLine__c pQLines: previousOppsQuoteLines ) {
            if(pQLines.SBQQ__Product__r.Renewal_Not_Required__c) {
                continue;
            }
            if(pQLines.SBQQ__Product__r.SBQQ__RenewalProduct__c != null) {
                continue; // native mapping resolves this line directly further down, no term calc needed
            }
            if(pQLines.SBQQ__Product__r.Edition__c != Null && isNonSubscriptionProduct(pQLines.SBQQ__Product__r.Family, pQLines.SBQQ__Product__r.Subscription_Model__c,pQLines.SBQQ__Product__r.SBQQ__SubscriptionType__c)){
                String productName = pQLines.SBQQ__Product__r.Name;
                System.debug('productName = '+productName);
                ProductsFinancialYear.add(Integer.valueOf(pQLines.SBQQ__Product__r.Financial_Year__c));
                ProductsFinancialYear.sort();
                Integer Size = ProductsFinancialYear.size();
                Integer MaxFY = ProductsFinancialYear[Size-1];
                Integer MinFY = ProductsFinancialYear[0];
                Integer OppTerm=MaxFY-MinFY + 1;
                OpportunityTermByOppId.put(pQLines.SBQQ__Quote__r.SBQQ__Opportunity2__c,OppTerm);
            }
        }
        //
        /***************************Kriti Changes*****************************************/
        renewalOppByPreviousOppId= getRenewalOpportunities(OwnerIdBYoppoId, renewalNotRequiredForOppIds,OrderIdBYoppoId); // opportunities to create
        /***************************Kriti Changes*****************************************/
        system.debug('renewalOppByPreviousOppId size = '+renewalOppByPreviousOppId.size());
        try{
        if (! renewalOppByPreviousOppId.isEmpty()) {
            Map<SBQQ__QuoteLine__c, String> newRenewalProductsNameByPreviousQLI = new Map<SBQQ__QuoteLine__c, String>();
            Map<Id, String> newRenewalProductsYearByPreviousP_Id  = new Map<Id, String>();
            Map<String, Id> previousProductIdByNewRenewalProductName = new Map<String, Id>();
            Integer maxEditionOrYear=0;
            Map<SBQQ__QuoteLine__c, Integer>maxEditionOrYearByQuoteline = new Map<SBQQ__QuoteLine__c, Integer>();
            for(SBQQ__QuoteLine__c pQLines: previousOppsQuoteLines ) {
                if(pQLines.SBQQ__Product__r.Renewal_Not_Required__c) {
                    continue; // per-line eligibility - this product does not renew
                }
                if(pQLines.SBQQ__Product__r.SBQQ__RenewalProduct__c != null) {
                    /*
                     * Preferred path: the catalogue already says what next year's product is.
                     * Resolve straight to it, no name/edition parsing, no runtime Product2 creation.
                     * The regex-derivation branch below is left in place but unreachable for any
                     * line that has this mapping - it still runs for products that do not have one
                     * yet, which is a data-quality gap to close in the catalogue, not a code path
                     * to keep patching.
                     */
                    existingNdNewlyCreatedRenewalProductByPreviousOPId.put(pQLines.SBQQ__Product__c, pQLines.SBQQ__Product__r.SBQQ__RenewalProduct__r);
                    continue;
                }
                if(isNonSubscriptionProduct(pQLines.SBQQ__Product__r.Family, pQLines.SBQQ__Product__r.Subscription_Model__c, pQLines.SBQQ__Product__r.SBQQ__SubscriptionType__c)){
                    String productName = pQLines.SBQQ__Product__r.Name;
                    if(pQLines.SBQQ__Product__r.Edition__c != Null) {
                        Integer oppDeallength = OpportunityTermByOppId.containsKey(pQLines.SBQQ__Quote__r.SBQQ__Opportunity2__c) ? OpportunityTermByOppId.get(pQLines.SBQQ__Quote__r.SBQQ__Opportunity2__c) : 0;
                        if(pQLines.SBQQ__Product__r.Name.Contains('Edition') ){
                             String editionToReplace;
                            String newRenewalProductsName;
                            String edition;
                            if(pQLines.SBQQ__Product__r.Edition__c.Contains('Edition')){
                                edition = String.valueOf(Integer.valueOf(pQLines.SBQQ__Product__r.Edition__c.remove('Edition ') )+  oppDeallength);
                                newRenewalProductsName = productName.replace(pQLines.SBQQ__Product__r.Edition__c.remove('Edition '), edition);
                                editionToReplace=String.valueOf(Integer.valueOf(pQLines.SBQQ__Product__r.Edition__c.remove('Edition ') ));
                                productNameWithoutYearByQuoteline.put(pQLines,productName.replace(pQLines.SBQQ__Product__r.Edition__c,''));


                            }else{
                               edition = String.valueOf(Integer.valueOf(pQLines.SBQQ__Product__r.Edition__c )+  oppDeallength);
                               newRenewalProductsName = productName.replace(pQLines.SBQQ__Product__r.Edition__c, edition);
                               editionToReplace=String.valueOf(Integer.valueOf(pQLines.SBQQ__Product__r.Edition__c ));
                               productNameWithoutYearByQuoteline.put(pQLines,productName.replace('Edition '+pQLines.SBQQ__Product__r.Edition__c,''));


                            }
                            System.debug('productName = '+productName +'----year = '+ pQLines.SBQQ__Product__r.Edition__c +'------oppDeallength = '+oppDeallength  +'---- newRenewalProductsName = '+newRenewalProductsName);
                            if(maxEditionOrYear<Integer.ValueOf(editionToReplace)){
                                maxEditionOrYearByQuoteline.put(pQLines,maxEditionOrYear);
                                maxEditionOrYear=Integer.ValueOf(editionToReplace);
                                system.debug('maxEditionOrYear'+maxEditionOrYear);
                            }
                            //productNameWithoutYearByQuoteline.put(pQLines,productName.replace(pQLines.SBQQ__Product__r.Edition__c,''));
                            editionYearByQuoteline.put(pQLines,Integer.ValueOf(editionToReplace));
                            System.Debug('productNameWithoutYearByQuoteline------>'+productNameWithoutYearByQuoteline);
                            System.debug('editionYearByQuoteline------>'+editionYearByQuoteline);
                            newRenewalProductsNameByPreviousQLI.put(pQLines,newRenewalProductsName);
                            newRenewalProductsYearByPreviousP_Id.put(pQLines.SBQQ__Product__c, edition); // doubt
                            previousProductIdByNewRenewalProductName.put(newRenewalProductsName, pQLines.SBQQ__Product__c);
                        }  else if(pQLines.SBQQ__Product__r.Edition__c.length() == 4){
                            Integer newYear= integer.valueOf(pQLines.SBQQ__Product__r.Edition__c)+oppDeallength;
                            Integer productYear=integer.valueOf(pQLines.SBQQ__Product__r.Edition__c);
                            if(maxEditionOrYear<productYear){
                                maxEditionOrYearByQuoteline.put(pQLines,maxEditionOrYear);
                                maxEditionOrYear=productYear;
                                system.debug('maxEditionOrYear'+maxEditionOrYear);
                            }
                            productNameWithoutYearByQuoteline.put(pQLines,productName.replace(String.valueOf(productYear),''));
                            editionYearByQuoteline.put(pQLines,productYear);
                            System.Debug('productNameWithoutYearByQuoteline------>'+productNameWithoutYearByQuoteline);
                            System.debug('editionYearByQuoteline------>'+editionYearByQuoteline);
                            String newRenewalProductsName = productName.replace(String.valueOf(pQLines.SBQQ__Product__r.Edition__c), String.valueOf(newYear));
                            System.debug('productName = '+productName +'-----year = '+ pQLines.SBQQ__Product__r.Edition__c+ '---newYear = '+ newYear + ' ---- oppDeallength = '+ oppDeallength + '---- newRenewalProductsName = '+newRenewalProductsName);
                            newRenewalProductsNameByPreviousQLI.put(pQLines, newRenewalProductsName);
                            System.debug('@@@@@@@159'+newRenewalProductsNameByPreviousQLI);
                            System.debug('@@@@@@@160'+newRenewalProductsNameByPreviousQLI.size());
                            newRenewalProductsYearByPreviousP_Id.put(pQLines.SBQQ__Product__c, String.valueOf(newYear));
                            previousProductIdByNewRenewalProductName.put(newRenewalProductsName, pQLines.SBQQ__Product__c);
                        }
                    }
                    if(pQLines.SBQQ__Product__r.Edition__c == '' || pQLines.SBQQ__Product__r.Edition__c == null) {
                        existingNdNewlyCreatedRenewalProductByPreviousOPId.put(pQLines.SBQQ__Product__c, pQLines.SBQQ__Product__r);
                    }
                }
            }
  /***************************************************Changes Done By Kriti On October 8*****************************************************/          
// Assuming maxEditionOrYear is set to a specific value
List<SBQQ__QuoteLine__c> keysToRemove = new List<SBQQ__QuoteLine__c>();
// Iterate through the map to identify keys with values matching maxEditionOrYear
for (SBQQ__QuoteLine__c key : editionYearByQuoteline.keySet()) {
    if (editionYearByQuoteline.get(key) != maxEditionOrYear) {
        keysToRemove.add(key);
    }
}
// Remove the identified keys from the map
for (SBQQ__QuoteLine__c keyToRemove : keysToRemove) {
    editionYearByQuoteline.remove(keyToRemove);
}
System.debug('editionYearByQuoteline-----> ' + editionYearByQuoteline);
productNameWithoutYearByQuoteline.keyset().removeAll(keysToRemove);
System.debug('productNameWithoutYearByQuoteline------->'+productNameWithoutYearByQuoteline);  
for (SBQQ__QuoteLine__c key : productNameWithoutYearByQuoteline.keySet()) {
    String value = productNameWithoutYearByQuoteline.get(key);
    quotelineByproductNameWithoutYear.put(value, key);
}
System.debug('quotelineByproductNameWithoutYear'+quotelineByproductNameWithoutYear);            
 /***********************************************Changes Done By Kriti On October 8*************************************************/           
            
            Map<Id,SBQQ__ProductOption__c> existingRenewalProductOptionByPreviousProductOptionId = new Map<Id,SBQQ__ProductOption__c>();
            Map<String, Id> existingProductIdByName = new Map<String, Id>();
            for(Product2 p : [
                SELECT Id, Name, Family,  ProductCode, Reporting_Stream__c, Financial_Year__c, SBQQ__PriceEditable__c,  SBQQ__PricingMethodEditable__c, CanUseRevenueSchedule, Division__c //PreviousYear_Product__c
                FROM Product2 
                WHERE Name IN :previousProductIdByNewRenewalProductName.keyset()
            ]) {
                existingRenewalProductByPreviousProductId.put(previousProductIdByNewRenewalProductName.get(p.Name), p); // maP<existingProductNAme, PreviousProductId> 
                // PreviousPRoductID  => new newRenewalExistingProduct
                existingProductIdByName.put(p.Name, p.Id);
            }
            renewalProductsByPreviousProductId = getRenewalProducts(existingProductIdByName.keySet(), newRenewalProductsYearByPreviousP_Id, newRenewalProductsNameByPreviousQLI); 
             sp = Database.setSavepoint();
            System.debug('renewalProductsByPreviousProductId.values().size()- '+renewalProductsByPreviousProductId.values().size());
            insertPartial(renewalProductsByPreviousProductId, 'Renewal product creation');
            System.debug('-------------------------Renewal Product Creation Done---------------------------------------');
            //product feature
            renewProductFeaturesPreviousPFIds = getProductFeatures(renewalProductsByPreviousProductId);
            System.debug('renewProductFeaturesPreviousPFIds size()--'+renewProductFeaturesPreviousPFIds.size());
            insertPartial(renewProductFeaturesPreviousPFIds, 'Renewal product feature creation');
            System.debug('_________________________________________________Product Feature creation done__________________________________________________________________________');
            
            Map<Id, Id> configuredByOptionalSKU = new Map<Id, Id>();
            List<SBQQ__ProductOption__c> previousProductOptions = [                    
                SELECT Id,Name, SBQQ__OptionalSKU__c, SBQQ__ConfiguredSKU__c, SBQQ__Type__c, SBQQ__Feature__c, 
                SBQQ__Quantity__c,SBQQ__QuantityEditable__c,SBQQ__Number__c,SBQQ__MinQuantity__c,SBQQ__Bundled__c,SBQQ__Selected__c,
                SBQQ__MaxQuantity__c,SBQQ__ProductOption__c.SBQQ__OptionalSKU__r.Family, SBQQ__OptionalSKU__r.Name,SBQQ__ConfiguredSKU__r.Name, SBQQ__ConfiguredSKU__r.Financial_Year__c,
                SBQQ__ConfiguredSKU__r.CurrencyIsoCode,SBQQ__OptionalSKU__r.CurrencyIsoCode, SBQQ__OptionalSKU__r.ProductCode,SBQQ__OptionalSKU__r.Reporting_Stream__c,SBQQ__OptionalSKU__r.Division__c,
                SBQQ__OptionalSKU__r.Financial_Year__c,CurrencyIsoCode 
                FROM SBQQ__ProductOption__c
                WHERE SBQQ__ConfiguredSKU__c IN :renewalProductsByPreviousProductId.keyset() AND SBQQ__OptionalSKU__c != null
            ];
            for (SBQQ__ProductOption__c productOption : previousProductOptions) {
                configuredByOptionalSKU.put(productOption.SBQQ__OptionalSKU__c, productOption.SBQQ__ConfiguredSKU__c);
            } 
            
            Map<String,Id> previousProductIDByRenewalOptionalProductName = new Map<String,Id>();
            Map<Id, String> renewalOptionalPrNameByPreviousOptionalProductId = new Map<Id, String>();
            For(Product2 OptionalProducts:[
                SELECT Id, 
                Name,Family,ProductCode,Division__c, SBQQ__PricingMethodEditable__c,Reporting_Stream__c,
                SBQQ__PriceEditable__c,CanUseRevenueSchedule,Subscription_Model__c,Financial_Year__c,Edition__c,SBQQ__SubscriptionType__c
                FROM Product2 WHERE Id in:configuredByOptionalSKU.keySet()
            ])  { // Optional Product SKU
                if(isNonSubscriptionProduct(OptionalProducts.Family, OptionalProducts.Subscription_Model__c,OptionalProducts.SBQQ__SubscriptionType__c)  && OptionalProducts.Edition__c != Null) {
                    
                    String pname = newRenewalProductsYearByPreviousP_Id.containskey(configuredByOptionalSKU.get(OptionalProducts.Id)) ? String.valueOf(newRenewalProductsYearByPreviousP_Id.get(configuredByOptionalSKU.get(OptionalProducts.Id))) : '';
                    System.debug('pname = '+pname);
                    
                    String renewalOptionalProductNameFormula;
                    if( OptionalProducts.Edition__c.Contains('Edition')  ) {
                        renewalOptionalProductNameFormula = OptionalProducts.Name.replace(String.valueOf(OptionalProducts.Edition__c.remove('Edition ')), String.valueOf(pname));
                    } else if( !OptionalProducts.Edition__c.Contains('Edition')  ) {
                        renewalOptionalProductNameFormula = OptionalProducts.Name.replace(String.valueOf(OptionalProducts.Edition__c), String.valueOf(pname));
                    }
                    if(renewalOptionalProductNameFormula != null) {
                        renewalOptionalPrNameByPreviousOptionalProductId.put(OptionalProducts.Id, renewalOptionalProductNameFormula);
                        newRenewalProductsYearByPreviousP_Id.put(OptionalProducts.Id, String.valueOf(pname));
                        previousProductIDByRenewalOptionalProductName.put(renewalOptionalProductNameFormula, OptionalProducts.Id);
                    }
                } else if(OptionalProducts.Edition__c == '' || OptionalProducts.Edition__c == null) {
                    existingNdNewlyCreatedRenewalProductByPreviousOPId.put(OptionalProducts.id,OptionalProducts);
                }
            }
            
            system.debug('renewalOptionalPrNameByPreviousOptionalProductId - '+renewalOptionalPrNameByPreviousOptionalProductId.values());
            Set<String> existingOptionalProductsName = new Set<String>();
            for(Product2 p : [ 
                SELECT Id,Name,Family,ProductCode,SBQQ__PriceEditable__c,SBQQ__PricingMethodEditable__c,CanUseRevenueSchedule,
                Financial_Year__c,Division__c,Reporting_Stream__c //PreviousYear_Product__c,
                FROM Product2 
                WHERE Name IN :previousProductIDByRenewalOptionalProductName.keyset()
            ]) {
                existingRenewalProductByPreviousProductId.put(previousProductIDByRenewalOptionalProductName.get(p.Name), p);                                        
                existingOptionalProductsName.add(p.Name);
            }
            
            //optional Products
            renewalOptionalProductsByPreviousOPId =  getRenewalOptionalProducts(configuredByOptionalSKU.keySet(), existingOptionalProductsName, newRenewalProductsYearByPreviousP_Id, renewalOptionalPrNameByPreviousOptionalProductId, renewalProductsByPreviousProductId);                
            system.debug('renewalOptionalProductsByPreviousOPId size --' +renewalOptionalProductsByPreviousOPId.size());
            insertPartial(renewalOptionalProductsByPreviousOPId, 'Renewal optional product creation');
            System.debug('_________________________________________________Optional Product creation done__________________________________________________________________________');
            
            existingNdNewlyCreatedRenewalProductByPreviousOPId.putAll(renewalProductsByPreviousProductId);
            existingNdNewlyCreatedRenewalProductByPreviousOPId.putAll(renewalOptionalProductsByPreviousOPId);
            existingNdNewlyCreatedRenewalProductByPreviousOPId.putAll(existingRenewalProductByPreviousProductId);
            /*------------Adding all newly created Renewals products and already existing renewal products in single map---------*/
            System.debug('existingNdNewlyCreatedRenewalProductByPreviousOPId size ='+existingNdNewlyCreatedRenewalProductByPreviousOPId.values().size());
            System.debug('existingNdNewlyCreatedRenewalProductByPreviousOPId size ='+existingNdNewlyCreatedRenewalProductByPreviousOPId);
            
            priceBookEntriesToBeCreated = getPricebook(renewalProductsByPreviousProductId, renewalOptionalProductsByPreviousOPId);
            System.debug('priceBookEntriesToBeCreated --'+priceBookEntriesToBeCreated);
            insertPartialList(priceBookEntriesToBeCreated, 'Renewal pricebook entry creation');
            System.debug('________________________________________________________PriceBook Entries creation Done___________________________________________________________________');
            
            
            
            //product option
            renewalProductOptionsByPreviousId =  getProductOptions(
                existingNdNewlyCreatedRenewalProductByPreviousOPId, renewalProductsByPreviousProductId, 
                renewProductFeaturesPreviousPFIds, previousProductOptions);
            System.debug('renewalProductOptionsByPreviousId --'+renewalProductOptionsByPreviousId);
            insertPartial(renewalProductOptionsByPreviousId, 'Renewal product option creation');
            Map<Id, Id> existingPproductOptionIdByPreviousId = new Map<Id, Id>();
            
            for(SBQQ__ProductOption__c PO : [
                SELECT Id, SBQQ__RenewalProductOption__c,SBQQ__ConfiguredSKU__c,SBQQ__OptionalSKU__c
                FROM SBQQ__ProductOption__c
                WHERE SBQQ__ConfiguredSKU__c IN :existingProductIdByName.values() 
            ]) {
                //AND SBQQ__OptionalSKU__c != null
                String k = PO.SBQQ__ConfiguredSKU__c+'---'+PO.SBQQ__OptionalSKU__c;
                //system.debug('keyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy =================================== '+k);
                mm.put(k, PO.Id);
                if(PO.SBQQ__RenewalProductOption__c != null){
                    existingPproductOptionIdByPreviousId.put(PO.SBQQ__RenewalProductOption__c, PO.Id);
                }
            }
            system.debug('mm size=================================== '+mm.size());
            system.debug('mm =================================== '+mm);
            System.debug('existingPproductOptionIdByPreviousId --------------->'+ existingPproductOptionIdByPreviousId);
            System.debug('existingPproductOptionIdByPreviousId size --------------->'+ existingPproductOptionIdByPreviousId.size());
            // creation of configuration rule
            renewalConfigRuleByPreConfigRuleId = createConfigurationRules(renewalProductsByPreviousProductId,renewProductFeaturesPreviousPFIds);
            system.debug(''+renewalProductsByPreviousProductId);
            insertPartial(renewalConfigRuleByPreConfigRuleId, 'Renewal configuration rule creation');
            system.debug('@@New Config Rule Size @@@'+renewalConfigRuleByPreConfigRuleId.values().size());
            
            // Creation of Optional Constrain
            Map<Id, SBQQ__OptionConstraint__c> renewalOptionalConsTrainByPreOptConsId =  createOptionConstraints(
                existingNdNewlyCreatedRenewalProductByPreviousOPId,  renewalProductOptionsByPreviousId,  renewalProductsByPreviousProductId);
            insertPartial(renewalOptionalConsTrainByPreOptConsId, 'Renewal option constraint creation');
            system.debug('@@New optional Constarin Size @@@'+renewalOptionalConstrainByPreOptConsId.values().size());
            
            // Creation of Content Slot
         
            
            /*----------------------------------------------------------Opportunity creation ----------------------------------------------------------*/
            insertPartial(renewalOppByPreviousOppId, 'Renewal opportunity creation');
            renewalPrimaryQuotesByPreviousQId = getRenewalPrimaryQuotes( OrderIdBYoppoId); // Primary Quotes to create

            system.debug('renewalPrimaryQuotesByPreviousQId size =  '+renewalPrimaryQuotesByPreviousQId.size());
            if (!renewalPrimaryQuotesByPreviousQId.isEmpty()) {
                insertPartial(renewalPrimaryQuotesByPreviousQId, 'Renewal quote creation');

                renewalOppsQuoteLinesToCreate = getQuoteLines(existingNdNewlyCreatedRenewalProductByPreviousOPId,previousOppsQuoteLines, renewalProductOptionsByPreviousId, existingPproductOptionIdByPreviousId);

                insertPartialList(renewalOppsQuoteLinesToCreate, 'Renewal quote line creation');
                /**********************************************Changes Done On September 8 For Quote field Update******************************************************************/   
              
                /**********************************************Changes Done On September 8 For Quote field Update******************************************************************/   
            
            }
            System.debug('Heapsize at line 244 ='+Limits.getHeapSize());
            
        } // close renewalOppByPreviousOppId.isEmpty if condition
       } catch(Exception ex) {
           /*
            * Every DML statement above now uses partial-success insert (see insertPartial /
            * insertPartialList) - a bad picklist value, a locked row, or a downstream flow
            * fault on one record no longer throws here and no longer takes the rest of the
            * batch down with it (fixes D3). Reaching this block means something genuinely
            * unexpected happened in the Apex itself (a null reference, a bad cast, a query
            * with zero rows, etc.), so rolling back to the last savepoint is still the right
            * call - the transaction may be in a half-built, inconsistent state.
            */
           Database.rollback(sp);
           //addError(ex.getMessage());
           String apexLogRecordTypeId = Schema.SObjectType.Flow_Log__c.getRecordTypeInfosByDeveloperName().get('Apex_Error').getRecordTypeId();
           List<Flow_Log__c> errorLogList = new List<Flow_Log__c>();
           for(String orderId : OwnerIdBYoppoId.Values())
           {
               Flow_Log__c errorLog = new Flow_Log__c();
               errorLog.Class_Name__c = 'RenewalOpportunityHandler2';
               errorLog.Error_Description__c = ex.getMessage() + ' Line Number : '+ex.getLineNumber();
               errorLog.Record_Name__c = 'RecordId: '+orderId;
               errorLog.recordtypeid = apexLogRecordTypeId;
               errorLogList.add(errorLog);
           }
           insert errorLogList;
           System.debug('=============The following exception has occurred: ' + ex.getMessage());


} 
              
    }
    
    
    private static List<SBQQ__QuoteLine__c> getQuoteLines(Map<Id, Product2> existingNdNewlyCreatedRenewalProductByPreviousOPId,List<SBQQ__QuoteLine__c> quoteLines, Map<Id, SBQQ__ProductOption__c> renewalProductOptionsByPreviousId, Map<Id, Id> existingPproductOptionIdByPreviousId ) {
        
        List<SBQQ__QuoteLine__c> returnRenewalOppsQuoteLinesToCreate = new List<SBQQ__QuoteLine__c>();
        /*****************************************************Kriti August 30 changes**********************************************************/
        Map<Id,id>QuotelineIdBynewOrExistingProductId=new Map<Id,id>();
        Map<Id,String>CurrencyIsoCodeByQuotelineId=new Map<Id,String>();
        Map<Id,String>priceBookIdByQuotelineId=new Map<Id,String>();
        Map<Id,Id>pbeIdByQuotelineId=new Map<Id,Id>();
        list<PricebookEntry> pbeList=new list<PricebookEntry>();
        for (SBQQ__QuoteLine__c prevQuoteLine : quoteLines) {
            //productIds.add(prevQuoteLine.SBQQ__Product__c);
            String productIdLookup = existingNdNewlyCreatedRenewalProductByPreviousOPId.containsKey(prevQuoteLine.SBQQ__Product__c) ? existingNdNewlyCreatedRenewalProductByPreviousOPId.get(prevQuoteLine.SBQQ__Product__c).Id : prevQuoteLine.SBQQ__Product__c;
            QuotelineIdBynewOrExistingProductId.put(productIdLookup,prevQuoteLine.id);
            CurrencyIsoCodeByQuotelineId.put(prevQuoteLine.Id,prevQuoteLine.SBQQ__Quote__r.CurrencyIsoCode);
            priceBookIdByQuotelineId.put(prevQuoteLine.Id,prevQuoteLine.SBQQ__Quote__r.SBQQ__PriceBook__c);
        }
        if(!QuotelineIdBynewOrExistingProductId.isEmpty() && !priceBookIdByQuotelineId.isEmpty() && !CurrencyIsoCodeByQuotelineId.isEmpty()){
            pbeList=[SELECT Id,Name, Pricebook2Id, Product2Id,CurrencyIsoCode, UnitPrice, ProductCode 
                     FROM PricebookEntry
                     where Product2Id IN:QuotelineIdBynewOrExistingProductId.keyset() and Pricebook2Id IN : priceBookIdByQuotelineId.values() and CurrencyIsoCode IN: CurrencyIsoCodeByQuotelineId.values()];
            System.debug('pbeList = '+pbeList);
        }
        for(PricebookEntry pbe : pbeList)  {
            
            if(!QuotelineIdBynewOrExistingProductId.isEmpty() && QuotelineIdBynewOrExistingProductId.containsKey(pbe.Product2Id)){
                pbeIdByQuotelineId.put(QuotelineIdBynewOrExistingProductId.get(pbe.Product2Id),pbe.id);
            }
            
            
        }
        System.debug('pbeIdByQuotelineId = '+pbeIdByQuotelineId);
        /****************************************************Kriti August 30 changes*******************************************************/
        
        for(SBQQ__QuoteLine__c prevQuoteLine : quoteLines)  {
            if(prevQuoteLine.SBQQ__Product__r.Renewal_Not_Required__c) {
                continue; // per-line eligibility - do not clone a line that does not renew
            }
            System.debug('contains = '+renewalPrimaryQuotesByPreviousQId.containsKey(prevQuoteLine.SBQQ__Quote__c));
            if(renewalPrimaryQuotesByPreviousQId.containsKey(prevQuoteLine.SBQQ__Quote__c)  ){
                SBQQ__QuoteLine__c newQuoteLineToBeCreated = prevQuoteLine.clone(false,True);     
                
                String productId = existingNdNewlyCreatedRenewalProductByPreviousOPId.containsKey(prevQuoteLine.SBQQ__Product__c) ? existingNdNewlyCreatedRenewalProductByPreviousOPId.get(prevQuoteLine.SBQQ__Product__c).Id : prevQuoteLine.SBQQ__Product__c;
                system.debug('existingNdNewlyCreatedRenewalProductByPreviousOPId'+existingNdNewlyCreatedRenewalProductByPreviousOPId);
                
                /**************************************Changes done by Kriti on october 8************************************************/
                String productName = existingNdNewlyCreatedRenewalProductByPreviousOPId.containsKey(prevQuoteLine.SBQQ__Product__c) ? existingNdNewlyCreatedRenewalProductByPreviousOPId.get(prevQuoteLine.SBQQ__Product__c).Name : prevQuoteLine.SBQQ__Product__r.Name;
                system.debug('productName'+productName);
                
                //String pattern = '\\b(\\d{4}|edition \\d+)\\b'; // This regex matches 4-digit years or "edition" followed by a number
                String pattern = '\\b(\\d{4}|edition\\d+|edition\\s\\d+|Edition\\d+|Edition\\s\\d+)\\b'; 

               // Use regex to remove the pattern from the product name
                productName = productName.replaceAll(pattern, '');
                System.debug('Modified product name: ' + productName); // This will print 'Modified product name: test  product'
                System.debug('quotelineByproductNameWithoutYear.containsKey(productName)----->'+quotelineByproductNameWithoutYear.containsKey(productName));
                if(!quotelineByproductNameWithoutYear.isEmpty() && quotelineByproductNameWithoutYear.containsKey(productName)){
                    newQuoteLineToBeCreated.SBQQ__Renewal__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__Renewal__c;
                    newQuoteLineToBeCreated.SBQQ__Existing__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__Existing__c;
                    newQuoteLineToBeCreated.SBQQ__PriorQuantity__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__PriorQuantity__c;
                    newQuoteLineToBeCreated.SBQQ__NetPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__NetPrice__c;
                    //newQuoteLineToBeCreated.SBQQ__EffectiveQuantity__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__EffectiveQuantity__c;
                    System.debug('newQuoteLineToBeCreated.SBQQ__Renewal__c'+newQuoteLineToBeCreated.SBQQ__Renewal__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__Existing__c'+newQuoteLineToBeCreated.SBQQ__Existing__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__PriorQuantity__c'+newQuoteLineToBeCreated.SBQQ__PriorQuantity__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__NetPrice__c'+newQuoteLineToBeCreated.SBQQ__NetPrice__c);
                    newQuoteLineToBeCreated.SBQQ__DiscountScheduleType__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__DiscountScheduleType__c;
                    newQuoteLineToBeCreated.SBQQ__PricingMethod__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__PricingMethod__c;
                    newQuoteLineToBeCreated.SBQQ__CarryoverLine__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__CarryoverLine__c;
                    newQuoteLineToBeCreated.SBQQ__Quantity__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__Quantity__c;
                    newQuoteLineToBeCreated.SBQQ__UpgradedQuantity__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__UpgradedQuantity__c;
                    newQuoteLineToBeCreated.SBQQ__AllowAssetRefund__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__AllowAssetRefund__c;
                    newQuoteLineToBeCreated.SBQQ__SubscriptionPricing__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__SubscriptionPricing__c;
                    newQuoteLineToBeCreated.SBQQ__ListPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__ListPrice__c;
                    newQuoteLineToBeCreated.SBQQ__CustomerPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__CustomerPrice__c;
                    newQuoteLineToBeCreated.SBQQ__NetPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__NetPrice__c;
                    newQuoteLineToBeCreated.SBQQ__SpecialPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__SpecialPrice__c;
                    newQuoteLineToBeCreated.SBQQ__RegularPrice__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__RegularPrice__c;
                    newQuoteLineToBeCreated.SBQQ__Discount__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__Discount__c;
                    newQuoteLineToBeCreated.SBQQ__AdditionalDiscountAmount__c=quotelineByproductNameWithoutYear.get(productName).SBQQ__AdditionalDiscountAmount__c;

                    System.debug('newQuoteLineToBeCreated.SBQQ__DiscountScheduleType__c'+newQuoteLineToBeCreated.SBQQ__DiscountScheduleType__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__PricingMethod__c'+newQuoteLineToBeCreated.SBQQ__PricingMethod__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__CarryoverLine__c'+newQuoteLineToBeCreated.SBQQ__CarryoverLine__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__Quantity__c'+newQuoteLineToBeCreated.SBQQ__Quantity__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__UpgradedQuantity__c'+newQuoteLineToBeCreated.SBQQ__UpgradedQuantity__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__AllowAssetRefund__c'+newQuoteLineToBeCreated.SBQQ__AllowAssetRefund__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__SubscriptionPricing__c'+newQuoteLineToBeCreated.SBQQ__SubscriptionPricing__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__ListPrice__c'+newQuoteLineToBeCreated.SBQQ__ListPrice__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__CustomerPrice__c'+newQuoteLineToBeCreated.SBQQ__CustomerPrice__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__NetPrice__c'+newQuoteLineToBeCreated.SBQQ__NetPrice__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__SpecialPrice__c'+newQuoteLineToBeCreated.SBQQ__SpecialPrice__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__Discount__c'+newQuoteLineToBeCreated.SBQQ__Discount__c);
                    System.debug('newQuoteLineToBeCreated.SBQQ__AdditionalDiscountAmount__c'+newQuoteLineToBeCreated.SBQQ__AdditionalDiscountAmount__c);

                    
                    //System.debug();
                    
                }
                /**********************************************Changes Done By Kriti On October 8************************************************/
                
                if(prevQuoteLine.SBQQ__ProductOption__c != null){
                    String s = existingNdNewlyCreatedRenewalProductByPreviousOPId.containsKey(prevQuoteLine.SBQQ__ProductOption__r.SBQQ__ConfiguredSKU__c) ? existingNdNewlyCreatedRenewalProductByPreviousOPId.get(prevQuoteLine.SBQQ__ProductOption__r.SBQQ__ConfiguredSKU__c).Id : null;
                    System.debug('s ==== '+s);
                    String k = s+'---'+productId;
                    String productOption;
                    System.debug('kkkkkkkkkkkkkkkkk::::::::::::::::::::'+k);
                    System.debug('mm.containskey(k)::::::::::::::::::::'+mm.containskey(k));
                    System.debug('mm::::::::::::::::::::'+mm);
                    System.debug('mm key set::::::::::::::::::::'+mm.keySet());
                    if(renewalProductOptionsByPreviousId != null && renewalProductOptionsByPreviousId.containskey(prevQuoteLine.SBQQ__ProductOption__c) ){
                        productOption = renewalProductOptionsByPreviousId.get(prevQuoteLine.SBQQ__ProductOption__c).Id;
                    } else if(mm != null && mm.containskey(k)){
                        productOption = mm.get(k);
                    }
                    else {
                        productOption = null;
                    }
                    newQuoteLineToBeCreated.SBQQ__ProductOption__c = productOption;
                }
                
                newQuoteLineToBeCreated.SBQQ__Quote__c = renewalPrimaryQuotesByPreviousQId.get(prevQuoteLine.SBQQ__Quote__c).Id;
                // system.debug('PO======'+renewalProductOptionsByPreviousId.get(prevQuoteLine.SBQQ__ProductOption__c) );
                
                newQuoteLineToBeCreated.SBQQ__Product__c = productId; 
                /****************************************August 25 kriti changes*************************************/
               
                if(pbeIdByQuotelineId.containsKey(prevQuoteLine.Id)  ){
                    newQuoteLineToBeCreated.SBQQ__PricebookEntryId__c=pbeIdByQuotelineId.get(prevQuoteLine.Id); 
                }
                //newQuoteLineToBeCreated.SBQQ__PricebookEntryId__c=pbe.id; 
                
                /****************************************August 25 kriti changes*************************************/
                returnRenewalOppsQuoteLinesToCreate.add(newQuoteLineToBeCreated);
                
                //renewalOppsQuoteLinesToCreate.add(newQuoteLineToBeCreated);
                
            }
        }
        
        return returnRenewalOppsQuoteLinesToCreate;
    }   
    
    /*****************************************************************CREATING RENEWAL PRODUCT CODE*************************************************************/
    @testVisible 
    private static Long getCalculatedProductCode(String productName) {
        Long year;
        String yearPattern = '\\d{11}';
        Pattern pattern = Pattern.compile(yearPattern);
        System.debug('pattern = '+pattern);
        Matcher matcher = pattern.matcher(productName);
        System.debug('matcher = '+matcher);
        
        if (matcher.find()) {
            String yearStr = matcher.group();
            year = Long.valueOf(yearStr);
            System.debug('Heapsize at line 264 ='+Limits.getHeapSize());
            
            return year;
        }
        System.debug('year = '+year);
        return 0;
    }
    
    /**************************************************************CHECKING FOR SUBSCRIPTION PRODUCTS*******************************************************************/
    @testVisible 
    private static Boolean isNonSubscriptionProduct(String productFamily, String subscriptionModel,String subscriptionType) {
        //System.debug('Heapsize at line 292 ='+Limits.getHeapSize());
        
        return  ((productFamily =='Book Sales' 
                  ||productFamily =='Events'||productFamily =='Advertising'||productFamily =='Subs – LexPro LMI'||productFamily =='Subs - Lexology Insight'
                  ||productFamily =='Expert Insight - Lexology In-Depth'||productFamily =='Expert Insight - GxRs'||productFamily =='Expert Insight - Lexology Panoramic'||productFamily =='Webinars'
                  ||productFamily =='Expert Insight - Lexology Panoramic'||productFamily =='Subs - Legal Monitor'||productFamily =='Subs - Docket navigator'||productFamily =='Law Careers Net'
                  ||productFamily =='Expert Insight - IP'||productFamily =='Performance Data - Lexology Index'|| productFamily =='Performance Data - GxR/IP'||productFamily =='AllHire')
                 && subscriptionModel !='Time-Based'&& (subscriptionType =='One-time'|| subscriptionType =='Renewable')	);
        
    }
    /**************************************************** create configuration rule for new renewal product ****************************************************/ 
    @testVisible 
    private static Map<Id, SBQQ__ConfigurationRule__c> createConfigurationRules(Map<Id, Product2> renewalProductsByPreviousProductId,  Map<Id, SBQQ__ProductFeature__c> renewProductFeaturesPreviousPFIds) {
        Map<Id,SBQQ__ConfigurationRule__c> newlyCreatedConfigurationRules =new Map<Id,SBQQ__ConfigurationRule__c>();
        for(SBQQ__ConfigurationRule__c configOnPreviousProducts: [
            SELECT SBQQ__Active__c,id,name,SBQQ__ProductRule__c,SBQQ__ProductFeature__c,SBQQ__Product__c 
            FROM SBQQ__ConfigurationRule__c 
            WHERE SBQQ__Product__c in:renewalProductsByPreviousProductId.keyset()]) 
        {
            String productId = renewalProductsByPreviousProductId.get(configOnPreviousProducts.SBQQ__Product__c).Id;
            String PreviousYearProductId =configOnPreviousProducts.SBQQ__Product__c;
            System.debug('PreviousYearProductId = '+PreviousYearProductId + ' ---- productId = '+productId);
            SBQQ__ConfigurationRule__c newConfigurationRulesToBeCreated=configOnPreviousProducts.clone(false,True);  
            newConfigurationRulesToBeCreated.SBQQ__Product__c=productId;
            //Lookup for feature
            if(!renewProductFeaturesPreviousPFIds.isEmpty() && configOnPreviousProducts.SBQQ__ProductFeature__c != null  && 
               renewProductFeaturesPreviousPFIds.ContainsKey(configOnPreviousProducts.SBQQ__ProductFeature__c) )
            {
                newConfigurationRulesToBeCreated.SBQQ__ProductFeature__c= renewProductFeaturesPreviousPFIds.get(configOnPreviousProducts.SBQQ__ProductFeature__c).Id;
            }
            System.debug('newlyCreatedConfigurationRules'+newlyCreatedConfigurationRules);
            newlyCreatedConfigurationRules.put(configOnPreviousProducts.Id,newConfigurationRulesToBeCreated);
            system.debug('newConfigurationRulesToBeCreated'+newConfigurationRulesToBeCreated );
        }
        System.debug('Heapsize at line 321 ='+Limits.getHeapSize());
        
        return newlyCreatedConfigurationRules;
    }
    
    /**************************************Creation of Optional Constrain for newly Created Renewal products**************************************/
    @testVisible 
    private static Map<Id,SBQQ__OptionConstraint__c> createOptionConstraints(Map<Id, Product2> alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId ,Map<Id,SBQQ__ProductOption__c> newlyCreatedProductOptionsVsPreviousProductOptionId,Map<id,product2> renewalProductsByPreviousProductId) {
        Map<Id,SBQQ__OptionConstraint__c> newlyCreatedOptionCostraints =new Map<Id,SBQQ__OptionConstraint__c>();
        for(SBQQ__OptionConstraint__c optionalConstraintsOnPreviousProducts:[
            SELECT SBQQ__Active__c,Name,SBQQ__ConstrainingOption__r.SBQQ__OptionalSKU__c,SBQQ__ConstrainedOption__r.SBQQ__OptionalSKU__c,SBQQ__OptionConstraintGroup__c,SBQQ__ConfiguredSKU__c 
            FROM SBQQ__OptionConstraint__c 
            WHERE SBQQ__ConfiguredSKU__c IN :renewalProductsByPreviousProductId.Keyset()]) {
                System.debug('OptionaConstraintsOnPreviousProducts'+optionalConstraintsOnPreviousProducts);
                String productId = alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId.get(optionalConstraintsOnPreviousProducts.SBQQ__ConfiguredSKU__c).Id;
                String PYProductIdForConstrainingOption = optionalConstraintsOnPreviousProducts.SBQQ__ConstrainingOption__r.SBQQ__OptionalSKU__c;	
                String PYProductIdForConstrainedOption = optionalConstraintsOnPreviousProducts.SBQQ__ConstrainedOption__r.SBQQ__OptionalSKU__c;
                Id newConstrainingProductOption = newlyCreatedProductOptionsVsPreviousProductOptionId.get(optionalConstraintsOnPreviousProducts.SBQQ__ConstrainingOption__c).Id;
                Id newConstrainedProductOption = newlyCreatedProductOptionsVsPreviousProductOptionId.get(optionalConstraintsOnPreviousProducts.SBQQ__ConstrainedOption__c).Id;
                System.debug('productId'+productId);
                SBQQ__OptionConstraint__c newOptionConstraintsToBeCreated=optionalConstraintsOnPreviousProducts.clone(false,True);  
                newOptionConstraintsToBeCreated.SBQQ__ConfiguredSKU__c=productId;
                System.debug('newOptionConstraintsToBeCreated'+newOptionConstraintsToBeCreated);
                System.debug('newlyCreatedOptionCostraints'+newlyCreatedOptionCostraints);
                if(newlyCreatedProductOptionsVsPreviousProductOptionId.ContainsKey(optionalConstraintsOnPreviousProducts.SBQQ__ConstrainingOption__c)){
                    newOptionConstraintsToBeCreated.SBQQ__ConstrainingOption__c=newConstrainingProductOption;
                    System.debug('newConstrainingProductOption'+newConstrainingProductOption);
                }
                if(newlyCreatedProductOptionsVsPreviousProductOptionId.ContainsKey(optionalConstraintsOnPreviousProducts.SBQQ__ConstrainedOption__c)){
                    newOptionConstraintsToBeCreated.SBQQ__ConstrainedOption__c=newConstrainedProductOption;
                    System.debug('newConstrainedProductOption'+newConstrainedProductOption);
                }
                newlyCreatedOptionCostraints.put(optionalConstraintsOnPreviousProducts.id,newOptionConstraintsToBeCreated);                    
            }
        System.debug('Heapsize at line 355 ='+Limits.getHeapSize());
        
        return newlyCreatedOptionCostraints;
    }
    /************************************************** Product Option Creation *********************************************************/
    @testVisible 
    private static Map<Id,SBQQ__ProductOption__c> getProductOptions(Map<Id, Product2> alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId, Map<Id, Product2> renewalProductsByPreviousProductId, Map<Id, SBQQ__ProductFeature__c> renewProductFeaturesPreviousPFIds, List<SBQQ__ProductOption__c> previousProductOptions) {
        Map<Id, SBQQ__ProductOption__c> renewalProductOptionsByPreviousId =new Map<Id, SBQQ__ProductOption__c>();
        System.debug('_____________________________to Create product option______________________________________________________________');
        for(SBQQ__ProductOption__c PrevProductOptions: previousProductOptions)
        {
            System.debug('PrevProductOptions.SBQQ__OptionalSKU__c = '+PrevProductOptions.SBQQ__OptionalSKU__c);
            SBQQ__ProductOption__c newProductOptionsToBeCreated = new SBQQ__ProductOption__c();
            newProductOptionsToBeCreated = PrevProductOptions.clone(false,true);
            newProductOptionsToBeCreated.SBQQ__OptionalSKU__c = alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId.containskey(PrevProductOptions.SBQQ__OptionalSKU__c) ? alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId.get(PrevProductOptions.SBQQ__OptionalSKU__c).Id : null;
            newProductOptionsToBeCreated.SBQQ__ConfiguredSKU__c = alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId.containskey(PrevProductOptions.SBQQ__ConfiguredSKU__c) ? alreadyExistingAndNewlyCreatedRenewalProductsByPreviousProductId.get(PrevProductOptions.SBQQ__ConfiguredSKU__c).Id : null;
            newProductOptionsToBeCreated.SBQQ__Feature__c= PrevProductOptions.SBQQ__Feature__c != null  && renewProductFeaturesPreviousPFIds.ContainsKey(PrevProductOptions.SBQQ__Feature__c) ? renewProductFeaturesPreviousPFIds.get(PrevProductOptions.SBQQ__Feature__c).Id : null;
            renewalProductOptionsByPreviousId.put(PrevProductOptions.Id,newProductOptionsToBeCreated);
        }
        System.debug('Heapsize at line 386 ='+Limits.getHeapSize());
        
        return renewalProductOptionsByPreviousId;
    }
    
    /************************************************************ content slot creation***********************************************************************/
    
    
    /**********************************************************PRODUCT FEATURES CREATION*****************************************************************/
    @testvisible 
    private static Map<Id,SBQQ__ProductFeature__c> getProductFeatures( Map<Id, Product2> renewalProductsByPreviousProductId) {
        Map<Id,SBQQ__ProductFeature__c> productFeaturesByPreviousPFId =new Map<Id,SBQQ__ProductFeature__c>();
        for(SBQQ__ProductFeature__c productFeature: [
            SELECT Id, Name, SBQQ__ConfiguredSKU__c, SBQQ__Number__c, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__OptionSelectionMethod__c,
            SBQQ__DynamicProductLookupFieldSet__c, SBQQ__DynamicProductFilterFieldSet__c, SBQQ__DiscountSchedule__c, SBQQ__Category__c, OwnerId, SBQQ__ConfigurationFieldSet__c, CurrencyIsoCode 
            FROM SBQQ__ProductFeature__c 
            WHERE SBQQ__ConfiguredSKU__c IN :renewalProductsByPreviousProductId.keyset()]) 
        {
            SBQQ__ProductFeature__c productFeatureToBeCreated=new SBQQ__ProductFeature__c();
            productFeatureToBeCreated = productFeature.clone(false,true);
            productFeatureToBeCreated.Name=productFeature.Name;
            productFeatureToBeCreated.SBQQ__ConfiguredSKU__c = renewalProductsByPreviousProductId.get(productFeature.SBQQ__ConfiguredSKU__c).Id;
            productFeaturesByPreviousPFId.put(productFeature.Id, productFeatureToBeCreated);              
        }
        System.debug('Heapsize at line 429 ='+Limits.getHeapSize());
        
        return productFeaturesByPreviousPFId;
    }
    
    /****************************************************RENEWAL PRODUCTS AND RENEWAL OPTIONAL PRODUCT PRICEBOOK CREATION********************************************************/
    @testVisible 
    private static List<PriceBookEntry> getPricebook(Map<Id, Product2> newRenewalProductAndPreviousP_Id, Map<Id, Product2> newRenewalPOptionsByPreviousP_Id) {
        List<PriceBookEntry> priceBookEntriesToBeCreated= new List<PriceBookEntry>();
        for(PricebookEntry pbe : [
            SELECT Id, Name, Pricebook2Id, Product2Id, CurrencyIsoCode,  UnitPrice, IsActive,  UseStandardPrice,  CreatedDate,  ProductCode, IsDeleted, IsArchived 
            FROM PricebookEntry 
            WHERE Product2Id IN : newRenewalProductAndPreviousP_Id.keySet() OR Product2Id IN : newRenewalPOptionsByPreviousP_Id.keySet()
            ORDER BY Pricebook2.IsStandard DESC, UnitPrice ASC]) 
        {
            System.debug('PriceBook++++++'+pbe);
            String productId = newRenewalProductAndPreviousP_Id.containskey(pbe.Product2Id) ? newRenewalProductAndPreviousP_Id.get(pbe.Product2Id).Id : newRenewalPOptionsByPreviousP_Id.get(pbe.Product2Id).Id ;
            
            PriceBookEntry newPBE =new PriceBookEntry();
            newPBE = pbe.clone(false,true);
            newPBE.IsActive =  true;
            newPBE.UnitPrice =pbe.UnitPrice;
            newPBE.Pricebook2Id = pbe.Pricebook2Id;
            newPBE.Product2Id = productId;
            newPBE.CurrencyIsoCode=pbe.CurrencyIsoCode;
            newPBE.UseStandardPrice=pbe.UseStandardPrice;
            priceBookEntriesToBeCreated.add(newPBE);
            
        }
        System.debug('Heapsize at line 470 ='+Limits.getHeapSize());
        
        return priceBookEntriesToBeCreated;
    }
    
    /****************************************************RENEWAL OPTIONAL PRODUCT CREATION*******************************************************/
    @testVisible 
    private static Map<Id, Product2> getRenewalOptionalProducts(Set<Id> previousOptionalProductsIds, Set<String> existingOptionalProducts, Map<Id,String> newRenewalProductsYearByPreviousP_Id, Map<Id, String> renewalOptionPrNameByPreviousOP_Id, Map<Id, Product2> renewalProductsByPreviousProductId) {
        Map<Id, Product2> renewalOptionalProductsByPreviousOPId = new Map<Id, Product2>();
        System.debug('Heapsize at line 543 ='+Limits.getHeapSize());
        For(Product2 OptionalProduct: [
            SELECT Id,Name,Family,ProductCode,Division__c,SBQQ__PricingMethodEditable__c,Reporting_Stream__c, SBQQ__PriceEditable__c,
            Bundle__c,SBQQ__Hidden__c,SBQQ__ExcludeFromOpportunity__c,CanUseRevenueSchedule,Financial_Year__c, Product_Budget_Date__c, 
            Edition__c, Product_Date__c,Publication__c,SBQQ__ConfigurationEvent__c,SBQQ__ConfigurationType__c, //PreviousYear_Product__c,
            Revenue_Stream__c,Brand__c,Product_Type__c,Product_Type_2__c,Product_Type_3__c,Reporting_Group__c,Event_Title_Edition__c,
            Event__c,SBQQ__SubscriptionType__c,SBQQ__SubscriptionTerm__c,Publication_Title__c,Event_Location_Country__c,
            SBQQ__QuantityEditable__c,SBQQ__AssetConversion__c,	SBQQ__OptionLayout__c,	
            SBQQ__HidePriceInSearchResults__c,Default_Tax_Code__c	,Team__c,Date_Logic_Group__c,SBQQ__Component__c,Content_Slot_Required__c
            FROM Product2 WHERE Id in:previousOptionalProductsIds
        ]) {
            system.debug('Product_Budget_Date__c = '+OptionalProduct.Product_Budget_Date__c + ' ----OptionalProduct Name - '+OptionalProduct.Name + '-----existingOptionalProducts.contains(OptionalProduct.Name) = '+existingOptionalProducts.contains(OptionalProduct.Name));
            if(!existingOptionalProducts.contains(OptionalProduct.Name) && !renewalProductsByPreviousProductId.CONTAINSKEY(OptionalProduct.id) && renewalOptionPrNameByPreviousOP_Id.containskey(OptionalProduct.id)) {
                System.debug('OptionalProduct.Name - '+OptionalProduct.Name + '@@@@@@ '+renewalOptionPrNameByPreviousOP_Id.get(OptionalProduct.Id));
                Product2 RenewalOptionalProductsToCreate =new Product2();
                
                RenewalOptionalProductsToCreate = OptionalProduct.clone(false,true);
                String pYear = newRenewalProductsYearByPreviousP_Id.get(OptionalProduct.id); 
                RenewalOptionalProductsToCreate.SBQQ__SubscriptionType__c='One-time';
                RenewalOptionalProductsToCreate.Name = renewalOptionPrNameByPreviousOP_Id.get(OptionalProduct.Id);
                RenewalOptionalProductsToCreate.IsActive = True;
                
                Integer prevEdition;
                if(OptionalProduct.Edition__c.Contains('Edition')){
                    prevEdition = Integer.valueOf(OptionalProduct.Edition__c.Remove('Edition '));
                } else {
                    prevEdition = Integer.valueOf(OptionalProduct.Edition__c);
                }
                
                Integer OppTerm = Integer.valueOf(pYear);
                OppTerm = OppTerm-prevEdition;
                system.debug('pYear = '+pYear + ' ------ prevEdition = '+prevEdition+ '     @@@ OpportunityTerm'+OppTerm);
                Long pc=getCalculatedProductCode(OptionalProduct.ProductCode);
                String newProductCode;
                if(pc!=0){
                    newProductCode=OptionalProduct.ProductCode.replace(String.valueOf(pc), String.valueOf(pc+OppTerm));
                    RenewalOptionalProductsToCreate.ProductCode =newProductCode;
                    System.debug('newProductCode - '+newProductCode);
                }
                RenewalOptionalProductsToCreate.Financial_Year__c = OptionalProduct.Financial_Year__c != null ? String.valueOf(Integer.valueOf(OptionalProduct.Financial_Year__c)  + OppTerm)  : null;
                RenewalOptionalProductsToCreate.Product_Budget_Date__c = OptionalProduct.Product_Budget_Date__c != null ? OptionalProduct.Product_Budget_Date__c.addYears(OppTerm) : null;
                String EditionNumber = OptionalProduct.Edition__c.replaceAll('Edition ', '' );
                if(OptionalProduct.Edition__c.Contains('Edition')){
                    RenewalOptionalProductsToCreate.Edition__c = 'Edition ' + String.valueOf(Integer.valueOf(EditionNumber) + OppTerm);
                } else {
                    RenewalOptionalProductsToCreate.Edition__c = String.valueOf(Integer.valueOf(EditionNumber) + OppTerm);
                }
                
                RenewalOptionalProductsToCreate.Product_Date__c = OptionalProduct.Product_Date__c != null ? OptionalProduct.Product_Date__c.addYears(OppTerm) : null;
                renewalOptionalProductsByPreviousOPId.put(OptionalProduct.Id, RenewalOptionalProductsToCreate) ;
            }
        }
        System.debug('Heapsize at line 532 ='+Limits.getHeapSize());
        return renewalOptionalProductsByPreviousOPId;
    }
    
    /************************************************************RENEWAL PRODUCTS CREATION***************************************************************/
    @testVisible     
    private static Map<Id, Product2> getRenewalProducts(Set<String> existingProductsName, Map<Id,String> newRenewalProductsYearByPreviousP_Id, Map<SBQQ__QuoteLine__c,String> newRenewalProductsNameByPreviousQLI) {
        Map<Id, Product2> renewalProductsByPreviousProductId = new Map<Id, Product2>();
        System.debug('Heapsize at line 614 ='+Limits.getHeapSize());
        for(SBQQ__QuoteLine__c ql: newRenewalProductsNameByPreviousQLI.keySet()) {
            if(ql.SBQQ__Product__r.Edition__c != null) {
                String pName = newRenewalProductsNameByPreviousQLI.get(ql);
                
                if(! existingProductsName.contains(pName) ) {
                    String pYear = newRenewalProductsYearByPreviousP_Id.get(ql.SBQQ__Product__c);
                    Integer OppTerm = OpportunityTermByOppId.get(ql.SBQQ__Quote__r.SBQQ__Opportunity2__c);
                    system.debug('pYear = '+pYear + '----pName = '+pName + '----- contains = '+existingProductsName.contains(pName));
                    Product2 renewalProduct = new Product2();
                    renewalProduct=ql.SBQQ__Product__r.clone(false,true);
                    Long pc = getCalculatedProductCode(ql.SBQQ__Product__r.ProductCode);
                    renewalProduct.ProductCode = pc != 0 ? ql.SBQQ__Product__r.ProductCode.replace(String.valueOf(pc), String.valueOf(pc+OppTerm)) : null;
                    renewalProduct.Name = pName;
                    renewalProduct.IsActive = True;
                    renewalProduct.SBQQ__SubscriptionType__c='One-time';
                    renewalProduct.Financial_Year__c = ql.SBQQ__Product__r.Financial_Year__c != null ? String.valueOf(Integer.valueOf(ql.SBQQ__Product__r.Financial_Year__c) + OppTerm) : null;
                    renewalProduct.Product_Budget_Date__c = ql.SBQQ__Product__r.Product_Budget_Date__c != null ? ql.SBQQ__Product__r.Product_Budget_Date__c.addYears(OppTerm) : null;
                    String EditionNumber = ql.SBQQ__Product__r.Edition__c.replaceAll('Edition ', '' );
                    renewalProduct.Edition__c = renewalProduct.Edition__c.Contains('Edition') ? 'Edition ' + String.valueOf(Integer.valueOf(EditionNumber) + OppTerm) : String.valueOf(Integer.valueOf(EditionNumber) + OppTerm);
                    renewalProduct.Product_Date__c = ql.SBQQ__Product__r.Product_Date__c != null ? ql.SBQQ__Product__r.Product_Date__c.addYears(OppTerm) : null;
                    renewalProduct.CanUseRevenueSchedule = ql.SBQQ__Product__r.CanUseRevenueSchedule;
                    renewalProductsByPreviousProductId.put(ql.SBQQ__Product__c, renewalProduct);
                }
            }
        }
        
        System.debug('Heapsize at line 567 ='+Limits.getHeapSize());
        return renewalProductsByPreviousProductId;
    }
    /**************************************************Renewal Quote Creation***********************************************/
    @testVisible 
    private static Map<Id,SBQQ__Quote__c> getRenewalPrimaryQuotes( Map<Id, Id> OrderIdBYoppoId) {
        Map<Id,SBQQ__Quote__c> renewalPrimaryQuotesByPreviousQuoteId =new Map<Id,SBQQ__Quote__c>();
        Map<Id, Order> triggeringOrderToUpdate;
         system.debug('OrderIdBYoppoId -- '+OrderIdBYoppoId);
        Map<Id, Order> orderRecByOrderId= new Map<Id,Order>( [Select Id,OpportunityId,ShippingStreet,ShippingCity,ShippingCountry,ShippingState,ShippingPostalCode,
                                                              BillingStreet,BillingCity,BillingCountry,BillingState,BillingPostalCode,Renewal_Opportunity__c,OwnerId
                                                              from order where id IN : OrderIdBYoppoId.values() ]);
        
        system.debug('orderRecByOrderId -- '+orderRecByOrderId);
        for(SBQQ__Quote__c pQuote: [SELECT Id,Name,SBQQ__Status__c,SBQQ__Primary__c,SBQQ__PriceBook__c,SBQQ__PricebookId__c,EditLinesFieldSetName__c,
                                    SBQQ__PrimaryContact__c,OwnerId,CurrencyIsoCode,SBQQ__Opportunity2__c,SBQQ__StartDate__c,SBQQ__EndDate__c,
                                    SBQQ__CustomerDiscount__c,SBQQ__BillingStreet__c,	SBQQ__BillingState__c,SBQQ__BillingPostalCode__c,
                                    SBQQ__BillingName__c,SBQQ__BillingCountry__c,SBQQ__BillingCity__c,SBQQ__ShippingStreet__c,SBQQ__ShippingState__c,	
                                    SBQQ__ShippingPostalCode__c,SBQQ__ShippingName__c,SBQQ__ShippingCountry__c,SBQQ__ShippingCity__c,
                                    SBQQ__Opportunity2__r.Previous_Order__r.BillingAddress,SBQQ__Opportunity2__r.Previous_Order__r.ShippingAddress
                                    FROM SBQQ__Quote__c  
                                    WHERE SBQQ__Opportunity2__c IN :renewalOppByPreviousOppId.keyset() AND SBQQ__Primary__c=True]) {
                                        Opportunity opp = renewalOppByPreviousOppId.get(pQuote.SBQQ__Opportunity2__c);
                                        SBQQ__Quote__c renewalQuote = new SBQQ__Quote__c();
                                        renewalQuote = pQuote.clone(false,true);
                                        renewalQuote.SBQQ__Opportunity2__c = opp.Id;
                                        Decimal termLengthInYear= opp.Deal_Length__c != null && opp.Deal_Length__c > 0 ? (opp.Deal_Length__c)/12 : 1; 
                                        
                                        if(!OrderIdBYoppoId.isEmpty() && OrderIdBYoppoId.containskey(pQuote.SBQQ__Opportunity2__c)) {
                                            String orderId = OrderIdBYoppoId.get(pQuote.SBQQ__Opportunity2__c);
                                            
                                            //if(orderRecByOrderId.containskey(orderId)) {
                                                renewalQuote.SBQQ__BillingStreet__c = orderRecByOrderId.get(orderId).BillingStreet;
                                                renewalQuote.SBQQ__BillingState__c = orderRecByOrderId.get(orderId).BillingState;
                                                renewalQuote.SBQQ__BillingPostalCode__c = orderRecByOrderId.get(orderId).BillingPostalCode;
                                                renewalQuote.SBQQ__BillingCountry__c = orderRecByOrderId.get(orderId).BillingCountry;
                                                renewalQuote.SBQQ__BillingCity__c = orderRecByOrderId.get(orderId).BillingCity;
                                                
                                                renewalQuote.SBQQ__ShippingStreet__c=orderRecByOrderId.get(orderId).ShippingStreet;
                                                renewalQuote.SBQQ__ShippingState__c=orderRecByOrderId.get(orderId).ShippingState;
                                                renewalQuote.SBQQ__ShippingPostalCode__c=orderRecByOrderId.get(orderId).ShippingPostalCode;
                                                renewalQuote.SBQQ__ShippingCountry__c=orderRecByOrderId.get(orderId).ShippingCountry;
                                                renewalQuote.SBQQ__ShippingCity__c=orderRecByOrderId.get(orderId).ShippingCity;
                                            //}
                                            
                                        }
                                        
                                        renewalQuote.SBQQ__Status__c = 'Draft';
                                        renewalQuote.OwnerId=opp.OwnerId;
                                        renewalQuote.SBQQ__PrimaryContact__c=pQuote.SBQQ__PrimaryContact__c;
                                        renewalQuote.SBQQ__StartDate__c = pQuote.SBQQ__StartDate__c != null ? pQuote.SBQQ__StartDate__c.addYears(termLengthInYear.intValue()) : null;
                                        renewalQuote.SBQQ__EndDate__c = pQuote.SBQQ__EndDate__c != null ? pQuote.SBQQ__EndDate__c.addYears(termLengthInYear.intValue()) : null;            
                                        renewalQuote.SBQQ__Primary__c = true;
                                        
                                        renewalPrimaryQuotesByPreviousQuoteId.put(pQuote.Id, renewalQuote);
                                    }
        System.debug('Heapsize at line 586 ='+Limits.getHeapSize());
        
        //Updating Renewal Opp Lookup field On Order
        triggeringOrderToUpdate = updatingTriggeringOrder(orderRecByOrderId,renewalOppByPreviousOppId);
                 if(! triggeringOrderToUpdate.IsEmpty()){
                    update triggeringOrderToUpdate.values();                    
                }
        System.debug('triggeringOrderToUpdate'+triggeringOrderToUpdate);
        /////Updating Renewal Opp Lookup field On Order
        return renewalPrimaryQuotesByPreviousQuoteId;
    }
    
    /*******************************************************RENEWAL OPPORTUNITY CREATION*************************************************************/
    @testVisible 
    
    /***************************************Kriti Changes *********************************/
    public static Map<Id,Opportunity> getRenewalOpportunities(Map<Id, Id> OwnerIdBYoppoId, Set<Id> renewalNotRequiredForOppIds,Map<Id, Id> orderIdByOppId) {
        
        
        /***************************Kriti Changes*****************************************/
        //private static Map<Id,Opportunity> getRenewalOpportunities(Map<Id, Id> OwnerIdBYoppoId, Set<Id> renewalNotRequiredForOppIds,Map<Id, Id>orderIdByOppId) {
        System.debug('OwnerIdBYoppoId.values()-->'+OwnerIdBYoppoId.values());
        Map<Id, Opportunity> renewalOppToBeCreatedByoppId= new Map<Id,Opportunity>();
        //Map<Id,User>UserIdByOppId=new Map<Id,User>([Select Id,Renewal_Opportunity_owner__c from User where id IN : OwnerIdBYoppoId.values() ]);                      
        
        Renewal_Opportunity_Settings__c renewalOpportunitySetting = Renewal_Opportunity_Settings__c.getOrgDefaults();
        
        System.debug('renewalNotRequiredForOppIds-->'+renewalNotRequiredForOppIds);
        System.debug('OwnerIdBYoppoId-->'+OwnerIdBYoppoId);
        list<Opportunity> listOfOpportunity = [Select Id,Name,AccountId,CurrencyIsoCode,LeadSource,Previous_Opportunity__c,Pricebook2Id,OwnerId,SBQQ__Renewal__c,CloseDate,Deal_Length__c,
                                               StageName,SBQQ__Ordered__c,Pardot_Form_Completion__c,Primary_Contact__c,Previous_Order__c,LastModifiedById,
                                               (SELECT PricebookEntry.Product2.Name,PricebookEntry.Product2.Financial_Year__c, PricebookEntry.Product2.Product_Date__c  FROM OpportunityLineItems 
                                                where PricebookEntry.Product2.Renewal_Not_Required__c = false AND 
                                               PricebookEntry.Product2.Financial_Year__c != NULL AND PricebookEntry.Product2.Product_Date__c != NULL 
                                               Order BY PricebookEntry.Product2.Financial_Year__c) 
                                               From Opportunity Where Id IN:OwnerIdBYoppoId.keySet() AND ID NOT IN: renewalNotRequiredForOppIds];
        for(Opportunity opp: listOfOpportunity) { 
           
            //--------------------------Logic Added By Vishal-----Start----
            Map<Integer,Date> financialYearToMinDateMap = new Map<Integer,Date>();
            if(! opp.OpportunityLineItems.isEmpty()){
                for(OpportunityLineItem OppLineItem : opp.OpportunityLineItems){
                    if(OppLineItem.PricebookEntry.Product2.Financial_Year__c != NULL && OppLineItem.PricebookEntry.Product2.Product_Date__c != NULL)
                    {
                        Integer financialYear = Integer.valueOf(OppLineItem.PricebookEntry.Product2.Financial_Year__c);
                        
                        if( !financialYearToMinDateMap.containsKey(financialYear )) {
                            financialYearToMinDateMap.put(financialYear, OppLineItem.PricebookEntry.Product2.Product_Date__c);
                        } else {
                            Date productDateInMap = financialYearToMinDateMap.get(financialYear);
                            if(productDateInMap > OppLineItem.PricebookEntry.Product2.Product_Date__c)
                                financialYearToMinDateMap.put(financialYear, OppLineItem.PricebookEntry.Product2.Product_Date__c);
                        }
                        
                    }
                }
            }
            //fetching the latest financial year among all the financial years
            Date closedDateOfRenewalOpp;
            if(financialYearToMinDateMap.size() > 0)
            {
                list<Integer> listOfYears = new list<Integer>(financialYearToMinDateMap.keySet());
                listOfYears.sort();
                Integer yearListSize = listOfYears.size();
                Integer maxYear = listOfYears[yearListSize-1];
                closedDateOfRenewalOpp = financialYearToMinDateMap.get(maxYear).addDays(renewalOpportunitySetting.No_of_Days_For_Close_Date__c == NULL ? 0 :  Integer.ValueOf(renewalOpportunitySetting.No_of_Days_For_Close_Date__c));
            }
            System.debug('financialYearToMinDateMap=> '+financialYearToMinDateMap);
            System.debug('closedDateOfRenewalOpp=> '+closedDateOfRenewalOpp);
             //--------------------------Logic Added By Vishal-----Start----
             
            Opportunity renewalOpp = opp.clone();
            renewalOpp.LeadSource='Renewal';
            
            if(opp.Name.length() >= 110 ){
                System.debug('opp.Name.length()'+opp.Name.length());
              renewalOpp.Name= opp.Name.substring(0, 100)+ ' - ' +'Renewal';

                //opp.Name = sizeString.substring(0, maxSize);
            }
            else{
                renewalOpp.Name= opp.Name+ ' - ' +'Renewal';
            }
            
            //renewalOpp.Name=opp.Name.length() >= 110?opp.Name.substring(0, 100)+ ' - ' +'Renewal':opp.Name+ ' - ' +'Renewal';
            renewalOpp.Previous_Opportunity__c= opp.Id;
            renewalOpp.Type='Repeat Business';
            renewalOpp.NextStep='Follow Up';
            //renewalOpp.SBQQ__Renewal__c= True;//new change Aug 25
            renewalOpp.StageName='Identify';
            //Previous order billing address
            renewalOpp.Previous_Order__c=  orderIdByOppId.containskey(Opp.Id) ? orderIdByOppId.get(Opp.Id) : null;
            System.debug('orderIdByOppId.get(Opp.Id)'+orderIdByOppId.get(Opp.Id));
            //System.debug('renewalOpp.Previous_Order__r.id'+renewalOpp.Previous_Order__r.id);
            
            system.debug('OpportunityTermByOppId.containsKey(opp.Id)'+OpportunityTermByOppId.containsKey(opp.Id));
            Decimal termLengthInYear=OpportunityTermByOppId.containsKey(opp.Id)?OpportunityTermByOppId.get(opp.Id):1;
            system.debug('termLengthInYear'+termLengthInYear);
            //-------------new logic of closed date of renewable opportunnity--------- Added By Vishal
            renewalOpp.CloseDate = closedDateOfRenewalOpp != NULL ? closedDateOfRenewalOpp : Date.Today();
            //renewalOpp.CloseDate= opp.CloseDate.addYears(termLengthInYear.intValue()); // Commented on 14 Nov 2024
            //Integer month = (opp.CloseDate.addYears(termLengthInYear.intValue()). month())-3; 
            renewalOpp.Next_Contact_Date__c = renewalOpp.CloseDate;// Commented on 14 Nov 2024 based upon new logic request-  opp.CloseDate.addYears(termLengthInYear.intValue()).addMonths(-3);
            System.debug('renewalOpp.Next_Contact_Date__c'+renewalOpp.Next_Contact_Date__c);
            renewalOpp.Deal_Length__c = (integer.valueOf(termLengthInYear))*12;
            renewalOpp.SBQQ__Ordered__c= false;
            renewalOpp.OwnerId=opp.OwnerId;
            system.debug('renewalOpp.OwnerId'+renewalOpp.OwnerId);
            renewalOppToBeCreatedByoppId.put(opp.Id, renewalOpp);
            
        }
        System.debug('Heapsize at line 613 ='+Limits.getHeapSize());
        
        return renewalOppToBeCreatedByoppId;
    }
    /***********************************************UPDATE TRIGGERING ORDER RENEWAL OPP FIELD********************************************************/
    private static Map<Id,Order> updatingTriggeringOrder(Map<Id,Order>orderRecByOrderId,Map<Id,Opportunity>renewalOppByPreviousOppId) {
        Map<Id,Order>orderToUpdateByOrderId=new Map<Id,Order>();
        for(Order o: [
            Select Id,Name,Renewal_Opportunity__c,OpportunityId
            From Order
            Where Id IN:orderRecByOrderId.keySet() 
        ]){
            System.debug('orderRecByOrderId.containskey(o.OpportunityId)'+orderRecByOrderId.containskey(o.OpportunityId));
            System.debug('renewalOppByPreviousOppId.containskey(o.OpportunityId)'+renewalOppByPreviousOppId.containskey(o.OpportunityId));
            if(renewalOppByPreviousOppId.containskey(o.OpportunityId)) {
                o.Renewal_Opportunity__c=renewalOppByPreviousOppId.get(o.OpportunityId).id;
                orderToUpdateByOrderId.put(o.id,o);
            }
        }
        System.debug('orderToUpdateByOrderId'+orderToUpdateByOrderId);
        return orderToUpdateByOrderId;
    }
    
        /***********************************************UPDATE TRIGGERING ORDER RENEWAL OPP FIELD********************************************************/

    
    
    
    /*****************************Kriti Changes For Delete Opportunity************************************************/
    
    public static void  deleteReducedOrderOpportunity(Map<Id, Id> reducedOrderIdBYoppoId) {
        Savepoint sp1 = Database.setSavepoint();
        try{
        System.debug('reducedOrderIdBYoppoId'+reducedOrderIdBYoppoId);
        list<Opportunity> renewalOpportunity =new list<Opportunity>();
        renewalOpportunity=[Select id ,name from Opportunity Where Previous_Order__c In:reducedOrderIdBYoppoId.keySet() and StageName <> 'Closed Won'];
        System.debug('renewalOpportunity'+renewalOpportunity);
        If(!renewalOpportunity.isEmpty()){
            system.debug('renewalOpportunity'+renewalOpportunity);
            delete renewalOpportunity;
        }
        }catch(Exception e){
            database.rollback(sp1);
        }
        
    }
    
    /*****************************Kriti Changes For Delete Opportunity************************************************/
}