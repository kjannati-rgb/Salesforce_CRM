public without sharing class OpportunityAnalyticsCreate {

    @TestVisible
    private static Boolean isRunning = false;

    // Test hook: when non-null, overrides the CMDT kill-switch lookup (always null in production).
    @TestVisible
    private static Boolean activeOverride;

    // Holds rolled-up values for one clean product code
    public class RollupValues {
        public Decimal totalValueGBP = 0;
        public Decimal acvGBP = 0;
        public Id productId;
        public String reportingStream;
    }

    public static void createRecords(List<Opportunity> currentOpportunities) {
        if (isRunning) {
            System.debug('Skipping due to recursion');
            return;
        }
        isRunning = true;

        // Wrap the whole body so the recursion guard is ALWAYS cleared — on early return
        // or exception — instead of staying stuck true for the rest of the transaction.
        try {

        if (!isFeatureActive()) {
            system.debug('Metadata settings Turned OFF');
            return;
        }
        system.debug('Metadata settings Turned ON');

        if (currentOpportunities == null || currentOpportunities.isEmpty()) {
            return;
        }

        // Collect current Opportunity Ids
        Set<Id> currentOpportunityIds = new Set<Id>();
        for (Opportunity opp : currentOpportunities) {
            if (opp.Id != null) {
                currentOpportunityIds.add(opp.Id);
            }
        }

        if (currentOpportunityIds.isEmpty()) {
            return;
        }

        // Query current opportunities with previous opportunity lookup
        Map<Id, Opportunity> currentOppMap = new Map<Id, Opportunity>([
            SELECT Id,
                   Previous_Opportunity__c,
                   CurrencyIsoCode,
                   Exchange_rate__c
            FROM Opportunity
            WHERE Id IN :currentOpportunityIds
        ]);

        if (currentOppMap.isEmpty()) {
            return;
        }

        // Collect all relevant Opportunity Ids (current + previous)
        Set<Id> allRelevantOpportunityIds = new Set<Id>();
        for (Opportunity opp : currentOppMap.values()) {
            allRelevantOpportunityIds.add(opp.Id);

            if (opp.Previous_Opportunity__c != null) {
                allRelevantOpportunityIds.add(opp.Previous_Opportunity__c);
            }
        }

        // Query all relevant opportunities so previous opportunity exchange rate is available
        Map<Id, Opportunity> allOppMap = new Map<Id, Opportunity>([
            SELECT Id,
                   CurrencyIsoCode,
                   Exchange_rate__c
            FROM Opportunity
            WHERE Id IN :allRelevantOpportunityIds
        ]);

        // Query all line items for both current and previous opportunities
        List<OpportunityLineItem> allLineItems = [
            SELECT Id,
                   OpportunityId,
                   Product2Id,
                   TotalPrice,
                   Total_Price_GBP__c,
                   Annual_Contract_Value__c,
                   Product2.Clean_Product_Code__c,
                   Product2.Reporting_Stream__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :allRelevantOpportunityIds
        ];

        // Bucket line items by OpportunityId
        Map<Id, List<OpportunityLineItem>> oliByOpportunityId = new Map<Id, List<OpportunityLineItem>>();
        for (OpportunityLineItem oli : allLineItems) {
            if (!oliByOpportunityId.containsKey(oli.OpportunityId)) {
                oliByOpportunityId.put(oli.OpportunityId, new List<OpportunityLineItem>());
            }
            oliByOpportunityId.get(oli.OpportunityId).add(oli);
        }

        // Query existing Opportunity Analytics records for all current opportunities
        // Product_Code__c is a formula field, so we use it for matching only
        List<Opportunity_Analytics__c> existingOAList = [
            SELECT Id,
                   Current_Opportunity__c,
                   Product_Code__c,
                   Current_Product__c,
                   Previous_Product__c,
                   CurrencyIsoCode,
                   TCV2__c,
                   PTCV2__c,
                   Annual_Contract_Value2__c,
                   Previous_Annual_Contract_Value2__c,
                   Reporting__c
            FROM Opportunity_Analytics__c
            WHERE Current_Opportunity__c IN :currentOpportunityIds
        ];

        // Map existing OA by composite key: OpportunityId|ProductCode
        Map<String, Opportunity_Analytics__c> existingOAByOppAndCode = new Map<String, Opportunity_Analytics__c>();
        for (Opportunity_Analytics__c oa : existingOAList) {
            if (String.isBlank(oa.Product_Code__c)) {
                continue;
            }

            String key = buildOppCodeKey(oa.Current_Opportunity__c, oa.Product_Code__c);
            existingOAByOppAndCode.put(key, oa);
        }

        List<Opportunity_Analytics__c> recordsToInsert = new List<Opportunity_Analytics__c>();
        List<Opportunity_Analytics__c> recordsToUpdate = new List<Opportunity_Analytics__c>();

        // Process each current opportunity
        for (Id currentOppId : currentOpportunityIds) {
            Opportunity currentOpp = currentOppMap.get(currentOppId);
            if (currentOpp == null) {
                continue;
            }

            Id previousOppId = currentOpp.Previous_Opportunity__c;

            Decimal currentExchangeRate = currentOpp.Exchange_rate__c != null
                ? currentOpp.Exchange_rate__c
                : 1;
            system.debug('exchangerate '+currentExchangeRate);

            Decimal previousExchangeRate = 1;
            if (previousOppId != null && allOppMap.containsKey(previousOppId)) {
                Opportunity previousOpp = allOppMap.get(previousOppId);
                previousExchangeRate = previousOpp.Exchange_rate__c != null
                    ? previousOpp.Exchange_rate__c
                    : 1;
                system.debug('exchangerate '+previousExchangeRate);
            }

            List<OpportunityLineItem> currentLineItems = oliByOpportunityId.containsKey(currentOppId)
                ? oliByOpportunityId.get(currentOppId)
                : new List<OpportunityLineItem>();

            List<OpportunityLineItem> previousLineItems = (previousOppId != null && oliByOpportunityId.containsKey(previousOppId))
                ? oliByOpportunityId.get(previousOppId)
                : new List<OpportunityLineItem>();

            // Roll up by clean product code
            Map<String, RollupValues> currentMap = buildRollupMap(currentLineItems);
            Map<String, RollupValues> previousMap = buildRollupMap(previousLineItems);

            // Union of product codes from current and previous opportunity
            Set<String> allCodes = new Set<String>();
            allCodes.addAll(currentMap.keySet());
            allCodes.addAll(previousMap.keySet());

            for (String code : allCodes) {
                RollupValues currentRollup = currentMap.containsKey(code)
                    ? currentMap.get(code)
                    : new RollupValues();

                RollupValues previousRollup = previousMap.containsKey(code)
                    ? previousMap.get(code)
                    : new RollupValues();

                // Skip if neither side has a product lookup
                if (currentRollup.productId == null && previousRollup.productId == null) {
                    continue;
                }

                // Convert current values using CURRENT opportunity exchange rate
                Decimal currentTCVLocal  = convertFromGBP(currentRollup.totalValueGBP, currentExchangeRate);
                Decimal currentACVLocal  = convertFromGBP(currentRollup.acvGBP, currentExchangeRate);

                // Convert previous values using PREVIOUS opportunity exchange rate
                Decimal previousTCVLocal = convertFromGBP(previousRollup.totalValueGBP, previousExchangeRate);
                Decimal previousACVLocal = convertFromGBP(previousRollup.acvGBP, previousExchangeRate);

                String oaKey = buildOppCodeKey(currentOppId, code);

                if (existingOAByOppAndCode.containsKey(oaKey)) {
                    Opportunity_Analytics__c existingOA = existingOAByOppAndCode.get(oaKey);

                    // Ensure OA currency matches current opportunity
                    existingOA.CurrencyIsoCode = currentOpp.CurrencyIsoCode;

                    // Current values (local currency using current opp exchange rate)
                    existingOA.TCV2__c = currentTCVLocal;
                    existingOA.Annual_Contract_Value2__c = currentACVLocal;
                    existingOA.Current_Product__c = currentRollup.productId;

                    // Previous values (local currency using previous opp exchange rate)
                    existingOA.PTCV2__c = previousTCVLocal;
                    existingOA.Previous_Annual_Contract_Value2__c = previousACVLocal;
                    existingOA.Previous_Product__c = previousRollup.productId;

                    // Reporting from current product, falling back to previous product
                    existingOA.Reporting__c = currentRollup.reportingStream == null
                        ? previousRollup.reportingStream
                        : currentRollup.reportingStream;

                    recordsToUpdate.add(existingOA);
                } else {
                    Opportunity_Analytics__c newOA = new Opportunity_Analytics__c();
                    newOA.Current_Opportunity__c = currentOppId;

                    // Ensure OA currency matches current opportunity
                    newOA.CurrencyIsoCode = currentOpp.CurrencyIsoCode;

                    // Product_Code__c is a formula field — do not set it
                    // It will derive from Current_Product__c / Previous_Product__c

                    // Current values (local currency using current opp exchange rate)
                    newOA.TCV2__c = currentTCVLocal;
                    newOA.Annual_Contract_Value2__c = currentACVLocal;
                    newOA.Current_Product__c = currentRollup.productId;

                    // Previous values (local currency using previous opp exchange rate)
                    newOA.PTCV2__c = previousTCVLocal;
                    newOA.Previous_Annual_Contract_Value2__c = previousACVLocal;
                    newOA.Previous_Product__c = previousRollup.productId;

                    // Reporting from current product
                    newOA.Reporting__c = currentRollup.reportingStream==null ? previousRollup.reportingStream: currentRollup.reportingStream;

                    recordsToInsert.add(newOA);
                }
            }
        }

        try{
            // DML outside loops
            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }
            if (!recordsToInsert.isEmpty()) {
                insert recordsToInsert;
            }
        } catch (Exception e) {
            system.debug(e.getmessage());
            String apexLogRecordTypeId = Schema.SObjectType.Flow_Log__c.getRecordTypeInfosByDeveloperName().get('Apex_Error').getRecordTypeId();
            List<Flow_Log__c> errorLogList = new List<Flow_Log__c>();
            {
                Flow_Log__c errorLog = new Flow_Log__c();
                errorLog.Class_Name__c = 'OpportunityAnalyticsCreate';
                errorLog.Error_Description__c = e.getMessage() + ' Line Number : '+e.getLineNumber();
                errorLog.Record_Name__c = 'OpportunityAnalyticsCreate';
                errorLog.recordtypeid = apexLogRecordTypeId;
                errorLogList.add(errorLog);
            }
            insert errorLogList;
        }

        } finally {
            isRunning = false;
        }
    }

    /**
     * Returns whether the feature is switched on via Opportunity_Analytics_Settings__mdt.
     * Reads the designated 'Switch' record explicitly — the org holds more than one record
     * of this type, so a bare LIMIT 1 picked an arbitrary row. getInstance() reads the
     * cached CMDT registry (no SOQL) and returns null when the record is missing, which is
     * a graceful "off". The activeOverride test hook lets tests exercise both paths.
     */
    @TestVisible
    private static Boolean isFeatureActive() {
        if (activeOverride != null) {
            return activeOverride;
        }
        Opportunity_Analytics_Settings__mdt setting = Opportunity_Analytics_Settings__mdt.getInstance('Switch');
        return setting != null && setting.IsActive__c == true;
    }

    /**
     * Convenience overload for a single Opportunity Id
     */
    public static void createRecords(Id currentOpportunityId) {
        if (currentOpportunityId == null) {
            return;
        }

        List<Opportunity> oppList = [
            SELECT Id
            FROM Opportunity
            WHERE Id = :currentOpportunityId
        ];

        createRecords(oppList);
    }

    /**
     * Convenience overload for a Set of Opportunity Ids
     */
    public static void createRecords(Set<Id> currentOpportunityIds) {
        if (currentOpportunityIds == null || currentOpportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> oppList = [
            SELECT Id
            FROM Opportunity
            WHERE Id IN :currentOpportunityIds
        ];

        createRecords(oppList);
    }

    /**
     * Rolls up line items by Product2.Clean_Product_Code__c
     *
     * Stores:
     * - totalValueGBP = sum(TotalPrice)
     * - acvGBP = sum(Annual_Contract_Value__c)
     * - productId = first Product2Id found for that code
     * - reportingStream = current product reporting stream
     */
    private static Map<String, RollupValues> buildRollupMap(List<OpportunityLineItem> lineItems) {
        Map<String, RollupValues> result = new Map<String, RollupValues>();

        for (OpportunityLineItem oli : lineItems) {
            String code = oli.Product2.Clean_Product_Code__c;

            if (String.isBlank(code)) {
                continue;
            }

            if (!result.containsKey(code)) {
                result.put(code, new RollupValues());
            }

            RollupValues rollup = result.get(code);

            // TCV source in GBP
            rollup.totalValueGBP += (oli.Totalprice == null ? 0 : oli.Totalprice);

            // ACV source assumed to be GBP
            rollup.acvGBP += (oli.Annual_Contract_Value__c == null ? 0 : oli.Annual_Contract_Value__c);

            if (rollup.productId == null) {
                rollup.productId = oli.Product2Id;
            }

            if (rollup.reportingStream == null) {
                rollup.reportingStream = String.valueOf(oli.Product2.Reporting_Stream__c);
            }
        }

        return result;
    }

    /**
     * Converts a GBP amount into local currency.
     * Current formula assumes:
     * local = GBP / Exchange_rate__c
     */
    private static Decimal convertFromGBP(Decimal amountGBP, Decimal exchangeRate) {
        if (amountGBP == null) {
            return 0;
        }
        if (exchangeRate == null || exchangeRate == 0) {
            return amountGBP;
        }
        system.debug('amount '+amountGBP);
        return amountGBP / exchangeRate;
    }

    /**
     * Composite key helper:
     * OpportunityId|ProductCode
     */
    private static String buildOppCodeKey(Id opportunityId, String code) {
        return String.valueOf(opportunityId) + '|' + String.valueOf(code);
    }

}