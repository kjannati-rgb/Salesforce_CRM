/**
 * Creates the successor Opportunity/Quote/QuoteLine/OpportunityLineItem for Closed Won
 * opportunities whose renewal-eligible line is a Renewal_Not_Required__c = true, edition-based
 * product with a defined SBQQ__RenewalProduct__c mapping (WTR 1000 and any other product using
 * the same convention, e.g. Panoramic). RenewalOpportunityHandler2 deliberately skips this
 * population (Renewal_Not_Required__c = true means "not a CPQ subscription renewal"); until
 * now nothing in the org created the next edition's opportunity for it, and the case that
 * started this work (00267129) traced the missing WTR 1000 2027 pipeline back to that gap -
 * this class replaces what had been a manual, ad hoc process.
 *
 * One quote line in, one successor Opportunity out - a source Closed Won opportunity with
 * both a Firm Profile and a Biography line produces two separate successor opportunities,
 * matching the shape of the real historical "Repeat Business" records this was reverse
 * engineered from (each carries exactly one product).
 *
 * Idempotent: a source line already covered by an existing successor (matched on
 * Previous_Opportunity__c + the target product) is skipped, not re-created, so this is safe
 * to run nightly and safe to re-run over the same backlog.
 */
public class EditionRenewalOpportunityBatch implements Database.Batchable<SObject>, Database.Stateful {

    /*
     * A PROD-wide dry run (case 00267129 follow-up) found this population is much larger than
     * WTR 1000 alone - 1,966 eligible-and-uncovered lines across dozens of product families
     * (IAM Patent 1000, GAR 100, Latin Lawyer LL250, IAM Strategy 300, and more), spanning back
     * to 2024. Running unscoped would create ~1,966 new pipeline opportunities in one shot,
     * well outside what the WTR case asked for. sourceProductNamePrefix lets a run be narrowed
     * to one product family (a Product2.Name LIKE 'prefix%' filter) so WTR 1000 could be fixed
     * first without touching the rest of that backlog.
     *
     * excludeProductNamePrefix is the inverse: run against everything except one family. Once
     * WTR 1000 was proven out, this was extended to cover the rest of the backlog except
     * Lexology Index (534 lines, by far the largest single family and a deliberately separate
     * decision, not included here).
     */
    private String sourceProductNamePrefix;
    private String excludeProductNamePrefix;

    public EditionRenewalOpportunityBatch() {
        this(null, null);
    }

    public EditionRenewalOpportunityBatch(String sourceProductNamePrefix) {
        this(sourceProductNamePrefix, null);
    }

    public EditionRenewalOpportunityBatch(String sourceProductNamePrefix, String excludeProductNamePrefix) {
        this.sourceProductNamePrefix = sourceProductNamePrefix;
        this.excludeProductNamePrefix = excludeProductNamePrefix;
    }

    private Id runId;
    private Integer evaluatedCount = 0;
    private Integer createdCount = 0;
    private Integer skippedCount = 0;
    private Integer failedCount = 0;
    private Map<String, Integer> skipReasonCounts = new Map<String, Integer>();
    private List<String> failureDetails = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Renewal_Run__c run = new Renewal_Run__c();
        String scopeSuffix = '';
        if (sourceProductNamePrefix != null) {
            scopeSuffix += ' - scoped to product name prefix "' + sourceProductNamePrefix + '"';
        }
        if (excludeProductNamePrefix != null) {
            scopeSuffix += ' - excluding product name prefix "' + excludeProductNamePrefix + '"';
        }
        run.Scope_Description__c = 'Edition-based renewal opportunity creation (Renewal_Not_Required__c = true, SBQQ__RenewalProduct__c mapped, non-Renewable)'
            + (scopeSuffix != '' ? scopeSuffix : ' - UNSCOPED');
        Map<String, String> scopeParams = new Map<String, String>();
        if (sourceProductNamePrefix != null) {
            scopeParams.put('sourceProductNamePrefix', sourceProductNamePrefix);
        }
        if (excludeProductNamePrefix != null) {
            scopeParams.put('excludeProductNamePrefix', excludeProductNamePrefix);
        }
        run.Scope_Parameters__c = scopeParams.isEmpty() ? null : JSON.serialize(scopeParams);
        run.Dry_Run__c = false;
        run.Start_Time__c = Datetime.now();
        run.Status__c = 'Running';
        insert run;
        runId = run.Id;

        String query = 'SELECT Id, SBQQ__Quote__c, SBQQ__Quantity__c, SBQQ__NetPrice__c, SBQQ__ListPrice__c, ' +
            'SBQQ__Quote__r.SBQQ__Opportunity2__c, SBQQ__Quote__r.SBQQ__Opportunity2__r.Name, ' +
            'SBQQ__Quote__r.SBQQ__Opportunity2__r.AccountId, SBQQ__Quote__r.SBQQ__Opportunity2__r.Account.Name, ' +
            'SBQQ__Quote__r.SBQQ__Opportunity2__r.OwnerId, SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode, ' +
            'SBQQ__Quote__r.SBQQ__Opportunity2__r.Pricebook2Id, SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__c, ' +
            'SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__r.Name, ' +
            'SBQQ__Quote__r.SBQQ__PriceBook__c, SBQQ__Quote__r.SBQQ__PricebookId__c, ' +
            'SBQQ__Product__c, SBQQ__Product__r.Name, ' +
            'SBQQ__Product__r.SBQQ__RenewalProduct__c, SBQQ__Product__r.SBQQ__RenewalProduct__r.Name, ' +
            'SBQQ__Product__r.SBQQ__RenewalProduct__r.Product_Date__c ' +
            'FROM SBQQ__QuoteLine__c ' +
            'WHERE SBQQ__Quote__r.SBQQ__Primary__c = true ' +
            'AND SBQQ__Quote__r.SBQQ__Opportunity2__r.StageName = \'Closed Won\' ' +
            'AND SBQQ__Quote__r.SBQQ__Opportunity2__r.Cancelled__c = false ' +
            'AND (SBQQ__Quote__r.SBQQ__Opportunity2__r.Amount >= 0 OR SBQQ__Quote__r.SBQQ__Opportunity2__r.Amount = null) ' +
            'AND SBQQ__Product__r.Renewal_Not_Required__c = true ' +
            'AND SBQQ__Product__r.SBQQ__RenewalProduct__c != null ' +
            'AND SBQQ__Product__r.SBQQ__SubscriptionType__c != \'Renewable\'';
        String sourceProductNamePrefixParam;
        if (sourceProductNamePrefix != null) {
            query += ' AND SBQQ__Product__r.Name LIKE :sourceProductNamePrefixParam';
            sourceProductNamePrefixParam = sourceProductNamePrefix + '%';
        }
        String excludeProductNamePrefixParam;
        if (excludeProductNamePrefix != null) {
            query += ' AND (NOT SBQQ__Product__r.Name LIKE :excludeProductNamePrefixParam)';
            excludeProductNamePrefixParam = excludeProductNamePrefix + '%';
        }
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SBQQ__QuoteLine__c> scope) {
        evaluatedCount += scope.size();

        Set<Id> sourceOppIds = new Set<Id>();
        for (SBQQ__QuoteLine__c line : scope) {
            sourceOppIds.add(line.SBQQ__Quote__r.SBQQ__Opportunity2__c);
        }

        Set<String> existingSuccessorKeys = new Set<String>();
        for (OpportunityLineItem oli : [
            SELECT Opportunity.Previous_Opportunity__c, Product2Id
            FROM OpportunityLineItem
            WHERE Opportunity.Previous_Opportunity__c IN :sourceOppIds
        ]) {
            existingSuccessorKeys.add(successorKey(oli.Opportunity.Previous_Opportunity__c, oli.Product2Id));
        }

        /*
         * A PROD dry run found source data quality issues this must not blindly reproduce:
         * some Closed Won opportunities carry duplicate zero (or negative, credit-note-style)
         * quote lines for the same product - e.g. one real $7,910 line plus five duplicate $0
         * lines on the same opportunity. Without these two guards this would create a junk $0
         * "renewal" opportunity per duplicate, and/or several successors for one real deal.
         */
        Set<String> keysSeenThisScope = new Set<String>();
        Map<SBQQ__QuoteLine__c, Opportunity> newOppByLine = new Map<SBQQ__QuoteLine__c, Opportunity>();
        for (SBQQ__QuoteLine__c line : scope) {
            Id sourceOppId = line.SBQQ__Quote__r.SBQQ__Opportunity2__c;
            Id targetProductId = line.SBQQ__Product__r.SBQQ__RenewalProduct__c;
            String key = successorKey(sourceOppId, targetProductId);

            if (line.SBQQ__NetPrice__c == null || line.SBQQ__NetPrice__c <= 0) {
                recordSkip('Zero or negative amount line - not a real renewal candidate');
                continue;
            }
            if (existingSuccessorKeys.contains(key)) {
                recordSkip('Already has a successor opportunity');
                continue;
            }
            if (keysSeenThisScope.contains(key)) {
                recordSkip('Duplicate source quote line for the same product - one successor already queued this run');
                continue;
            }
            keysSeenThisScope.add(key);

            Opportunity newOpp = buildOpportunity(line);
            newOppByLine.put(line, newOpp);
        }

        if (newOppByLine.isEmpty()) {
            return;
        }

        List<SBQQ__QuoteLine__c> orderedLines = new List<SBQQ__QuoteLine__c>(newOppByLine.keySet());
        List<Opportunity> oppsToInsert = new List<Opportunity>();
        for (SBQQ__QuoteLine__c line : orderedLines) {
            oppsToInsert.add(newOppByLine.get(line));
        }
        List<Database.SaveResult> oppResults = Database.insert(oppsToInsert, false);

        Map<Id, Id> newOppIdByPricebookEntryLookupKey = new Map<Id, Id>();
        List<SBQQ__QuoteLine__c> succeededLines = new List<SBQQ__QuoteLine__c>();
        for (Integer i = 0; i < oppResults.size(); i++) {
            SBQQ__QuoteLine__c line = orderedLines[i];
            if (oppResults[i].isSuccess()) {
                succeededLines.add(line);
            } else {
                failedCount++;
                logFailure(line.SBQQ__Quote__r.SBQQ__Opportunity2__c, 'Opportunity creation', oppResults[i].getErrors());
            }
        }

        if (succeededLines.isEmpty()) {
            return;
        }

        createRenewalQuoteAndLine(succeededLines, newOppByLine);
    }

    private void createRenewalQuoteAndLine(List<SBQQ__QuoteLine__c> succeededLines, Map<SBQQ__QuoteLine__c, Opportunity> newOppByLine) {
        Set<Id> targetProductIds = new Set<Id>();
        Set<Id> pricebookIds = new Set<Id>();
        Set<String> currencyCodes = new Set<String>();
        for (SBQQ__QuoteLine__c line : succeededLines) {
            targetProductIds.add(line.SBQQ__Product__r.SBQQ__RenewalProduct__c);
            if (line.SBQQ__Quote__r.SBQQ__PriceBook__c != null) {
                pricebookIds.add(line.SBQQ__Quote__r.SBQQ__PriceBook__c);
            }
            currencyCodes.add(line.SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode);
        }

        Map<String, Id> pbeIdByProductPricebookCurrency = new Map<String, Id>();
        if (!targetProductIds.isEmpty() && !pricebookIds.isEmpty()) {
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, Pricebook2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Product2Id IN :targetProductIds AND Pricebook2Id IN :pricebookIds
                    AND CurrencyIsoCode IN :currencyCodes AND IsActive = true
            ]) {
                pbeIdByProductPricebookCurrency.put(pbe.Product2Id + '|' + pbe.Pricebook2Id + '|' + pbe.CurrencyIsoCode, pbe.Id);
            }
        }

        Map<SBQQ__QuoteLine__c, SBQQ__Quote__c> newQuoteByLine = new Map<SBQQ__QuoteLine__c, SBQQ__Quote__c>();
        for (SBQQ__QuoteLine__c line : succeededLines) {
            Opportunity newOpp = newOppByLine.get(line);
            SBQQ__Quote__c newQuote = new SBQQ__Quote__c();
            newQuote.SBQQ__Account__c = newOpp.AccountId;
            newQuote.SBQQ__Opportunity2__c = newOpp.Id;
            newQuote.SBQQ__Primary__c = true;
            newQuote.SBQQ__Status__c = 'Draft';
            newQuote.SBQQ__PriceBook__c = line.SBQQ__Quote__r.SBQQ__PriceBook__c;
            newQuote.SBQQ__PricebookId__c = line.SBQQ__Quote__r.SBQQ__PricebookId__c;
            newQuote.CurrencyIsoCode = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode;
            newQuote.SBQQ__PrimaryContact__c = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__c;
            newQuoteByLine.put(line, newQuote);
        }

        List<SBQQ__QuoteLine__c> orderedLines = new List<SBQQ__QuoteLine__c>(newQuoteByLine.keySet());
        List<SBQQ__Quote__c> quotesToInsert = new List<SBQQ__Quote__c>();
        for (SBQQ__QuoteLine__c line : orderedLines) {
            quotesToInsert.add(newQuoteByLine.get(line));
        }
        List<Database.SaveResult> quoteResults = Database.insert(quotesToInsert, false);

        List<SBQQ__QuoteLine__c> quoteLinesToInsert = new List<SBQQ__QuoteLine__c>();
        List<OpportunityLineItem> oliToInsert = new List<OpportunityLineItem>();
        List<Opportunity> succeededOpps = new List<Opportunity>();

        for (Integer i = 0; i < quoteResults.size(); i++) {
            SBQQ__QuoteLine__c sourceLine = orderedLines[i];
            Opportunity newOpp = newOppByLine.get(sourceLine);
            if (!quoteResults[i].isSuccess()) {
                failedCount++;
                logFailure(sourceLine.SBQQ__Quote__r.SBQQ__Opportunity2__c, 'Renewal quote creation', quoteResults[i].getErrors());
                continue;
            }

            Id targetProductId = sourceLine.SBQQ__Product__r.SBQQ__RenewalProduct__c;
            String pbeKey = targetProductId + '|' + sourceLine.SBQQ__Quote__r.SBQQ__PriceBook__c + '|' + sourceLine.SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode;
            Id pbeId = pbeIdByProductPricebookCurrency.get(pbeKey);
            if (pbeId == null) {
                failedCount++;
                logFailure(sourceLine.SBQQ__Quote__r.SBQQ__Opportunity2__c, 'Renewal quote line creation',
                    'No active PricebookEntry found for renewal product ' + targetProductId
                    + ' on pricebook ' + sourceLine.SBQQ__Quote__r.SBQQ__PriceBook__c
                    + ' in ' + sourceLine.SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode);
                continue;
            }

            SBQQ__QuoteLine__c newLine = new SBQQ__QuoteLine__c();
            newLine.SBQQ__Quote__c = quotesToInsert[i].Id;
            newLine.SBQQ__Product__c = targetProductId;
            newLine.SBQQ__PricebookEntryId__c = pbeId;
            newLine.SBQQ__Quantity__c = sourceLine.SBQQ__Quantity__c;
            newLine.SBQQ__ListPrice__c = sourceLine.SBQQ__ListPrice__c;
            newLine.SBQQ__NetPrice__c = sourceLine.SBQQ__NetPrice__c;
            newLine.SBQQ__CustomerPrice__c = sourceLine.SBQQ__NetPrice__c;
            quoteLinesToInsert.add(newLine);

            OpportunityLineItem oli = new OpportunityLineItem();
            oli.OpportunityId = newOpp.Id;
            oli.PricebookEntryId = pbeId;
            oli.Quantity = sourceLine.SBQQ__Quantity__c;
            oli.UnitPrice = sourceLine.SBQQ__NetPrice__c;
            Date productDate = sourceLine.SBQQ__Product__r.SBQQ__RenewalProduct__r.Product_Date__c;
            if (productDate != null) {
                oli.Start_Date_SUN_Report__c = productDate.addDays(13);
                oli.End_Date_SUN_Report__c = oli.Start_Date_SUN_Report__c.addMonths(12).addDays(-1);
            }
            oliToInsert.add(oli);

            succeededOpps.add(newOpp);
        }

        insertPartialList(quoteLinesToInsert, 'Renewal quote line creation');
        insertPartialList(oliToInsert, 'Renewal opportunity line item creation');
        createdCount += succeededOpps.size();
    }

    private Opportunity buildOpportunity(SBQQ__QuoteLine__c line) {
        String targetProductName = line.SBQQ__Product__r.SBQQ__RenewalProduct__r.Name;
        String accountName = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Account.Name;
        String contactName = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__r != null
            ? line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__r.Name : '';
        String currencyCode = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.CurrencyIsoCode;
        Decimal amount = line.SBQQ__NetPrice__c;

        String name = targetProductName + ' | Repeat Business | ' + accountName + ' | ' + amount + ' ' + currencyCode + ' | ' + contactName;
        if (name.length() > 120) {
            name = name.substring(0, 117) + '...';
        }

        Date productDate = line.SBQQ__Product__r.SBQQ__RenewalProduct__r.Product_Date__c;
        Date closeDate = productDate != null ? productDate.addDays(-1) : Date.today();

        Opportunity newOpp = new Opportunity();
        newOpp.Name = name;
        newOpp.AccountId = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.AccountId;
        newOpp.OwnerId = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.OwnerId;
        newOpp.CurrencyIsoCode = currencyCode;
        newOpp.Amount = amount;
        newOpp.StageName = 'Identify';
        newOpp.CloseDate = closeDate;
        newOpp.Type = 'Repeat Business';
        newOpp.LeadSource = 'Renewal';
        newOpp.Previous_Opportunity__c = line.SBQQ__Quote__r.SBQQ__Opportunity2__c;
        newOpp.Previous_Order__c = findPreviousOrderId(line.SBQQ__Quote__r.SBQQ__Opportunity2__c);
        newOpp.Primary_Contact__c = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Primary_Contact__c;
        newOpp.Pricebook2Id = line.SBQQ__Quote__r.SBQQ__Opportunity2__r.Pricebook2Id;
        return newOpp;
    }

    private Map<Id, Id> previousOrderIdByOppId;

    private Id findPreviousOrderId(Id sourceOppId) {
        if (previousOrderIdByOppId == null) {
            previousOrderIdByOppId = new Map<Id, Id>();
        }
        if (!previousOrderIdByOppId.containsKey(sourceOppId)) {
            List<Order> orders = [
                SELECT Id FROM Order WHERE OpportunityId = :sourceOppId AND Status = 'Activated' ORDER BY ActivatedDate DESC LIMIT 1
            ];
            previousOrderIdByOppId.put(sourceOppId, orders.isEmpty() ? null : orders[0].Id);
        }
        return previousOrderIdByOppId.get(sourceOppId);
    }

    private String successorKey(Id sourceOppId, Id targetProductId) {
        return sourceOppId + '|' + targetProductId;
    }

    private void recordSkip(String reason) {
        skippedCount++;
        Integer current = skipReasonCounts.containsKey(reason) ? skipReasonCounts.get(reason) : 0;
        skipReasonCounts.put(reason, current + 1);
    }

    private void logFailure(Id sourceOppId, String stepLabel, List<Database.Error> errors) {
        String errorText = '';
        for (Database.Error err : errors) {
            errorText += err.getStatusCode() + ': ' + err.getMessage() + '; ';
        }
        logFailure(sourceOppId, stepLabel, errorText);
    }

    private void logFailure(Id sourceOppId, String stepLabel, String errorText) {
        failureDetails.add(stepLabel + ' failed for source opportunity ' + sourceOppId + ' - ' + errorText);
        Flow_Log__c errorLog = new Flow_Log__c();
        errorLog.Class_Name__c = 'EditionRenewalOpportunityBatch';
        errorLog.Error_Description__c = stepLabel + ' failed - ' + errorText;
        errorLog.Record_Name__c = 'RecordId: ' + sourceOppId;
        insert errorLog;
    }

    private void insertPartialList(List<SObject> records, String stepLabel) {
        if (records.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.insert(records, false);
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                failedCount++;
                logFailure(null, stepLabel, result.getErrors());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Renewal_Run__c run = new Renewal_Run__c(Id = runId);
        run.End_Time__c = Datetime.now();
        run.Records_Evaluated__c = evaluatedCount;
        run.Renewals_Created__c = createdCount;
        run.Records_Skipped__c = skippedCount;
        run.Records_Failed__c = failedCount;

        List<String> breakdown = new List<String>();
        for (String reason : skipReasonCounts.keySet()) {
            breakdown.add(reason + ': ' + skipReasonCounts.get(reason));
        }
        run.Skip_Reason_Breakdown__c = String.join(breakdown, '\n');
        run.Failure_Detail__c = String.join(failureDetails, '\n');
        run.Status__c = failedCount > 0 ? 'Completed with Errors' : 'Completed';
        update run;
    }
}
