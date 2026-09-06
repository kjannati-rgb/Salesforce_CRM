/**
 * Closes the "Contract exists but was never renewed" gap using Salesforce CPQ's own
 * SBQQ.RenewalAPI, rather than hand-rolling a clone (the approach EditionRenewalOpportunityBatch
 * uses for the separate "no Contract at all" gap). This population already went through a
 * proper Order-to-Contract conversion, so the Asset/Subscription tracking RenewalAPI needs
 * already exists - it just needs someone (previously a manual click) to trigger the renewal.
 *
 * Scoped to "WTR 1000" (Contract.Original_Opportunity__c prefix, not year-locked) to match
 * the same deliberate scoping decision as EditionRenewalOpportunityBatch - the wider
 * multi-product backlog a PROD dry run turned up is a separate decision, not included here.
 */
public class ContractRenewalApiBatch implements Database.Batchable<SObject>, Database.Stateful {

    private String originalOpportunityNamePrefix;

    public ContractRenewalApiBatch() {
        this(null);
    }

    public ContractRenewalApiBatch(String originalOpportunityNamePrefix) {
        this.originalOpportunityNamePrefix = originalOpportunityNamePrefix;
    }

    private Id runId;
    private Integer evaluatedCount = 0;
    private Integer renewedCount = 0;
    private Integer failedCount = 0;
    private List<String> failureDetails = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Renewal_Run__c run = new Renewal_Run__c();
        run.Scope_Description__c = 'Contract renewal via SBQQ.RenewalAPI (existing Contracts with SBQQ__RenewalForecast__c = true, no renewal opportunity yet)'
            + (originalOpportunityNamePrefix != null ? ' - scoped to original opportunity prefix "' + originalOpportunityNamePrefix + '"' : ' - UNSCOPED');
        run.Scope_Parameters__c = originalOpportunityNamePrefix != null ? JSON.serialize(new Map<String, String>{ 'originalOpportunityNamePrefix' => originalOpportunityNamePrefix }) : null;
        run.Dry_Run__c = false;
        run.Start_Time__c = Datetime.now();
        run.Status__c = 'Running';
        insert run;
        runId = run.Id;

        /*
         * SBQQ.RenewalAPI.renewContracts() reads far more fields off each Contract sObject
         * internally than this class itself touches - a query that is too narrow throws
         * "SObject row was retrieved via SOQL without querying the requested field" from
         * inside the managed package (found by testing against a realistic Contract in
         * KJDEV). This list matches every field populated on real, successfully-renewed
         * Contracts in PROD.
         */
        String query = 'SELECT Id, AccountId, CurrencyIsoCode, StartDate, EndDate, ContractTerm, OwnerId, Status, ' +
            'SBQQ__Order__c, SBQQ__Opportunity__c, SBQQ__Quote__c, SBQQ__RenewalOpportunity__c, ' +
            'SBQQ__RenewalForecast__c, SBQQ__RenewalPricebookId__c, SBQQ__RenewalTerm__c, SBQQ__RenewalOwner__c, ' +
            'SBQQ__RenewalQuoted__c, SBQQ__AmendmentRenewalBehavior__c, SBQQ__DefaultRenewalContactRoles__c, ' +
            'SBQQ__DefaultRenewalPartners__c, SBQQ__DisableAmendmentCoTerm__c, SBQQ__Evergreen__c, ' +
            'SBQQ__MasterContract__c, SBQQ__PreserveBundleStructureUponRenewals__c, ' +
            'SBQQ__SubscriptionQuantitiesCombined__c, Primary_Contact__c, Original_Opportunity__c ' +
            'FROM Contract ' +
            'WHERE Status = \'Activated\' ' +
            'AND SBQQ__RenewalForecast__c = true ' +
            'AND SBQQ__RenewalOpportunity__c = null ' +
            'AND SBQQ__Opportunity__r.Cancelled__c = false';
        String originalOpportunityNamePrefixParam;
        if (originalOpportunityNamePrefix != null) {
            query += ' AND Original_Opportunity__c LIKE :originalOpportunityNamePrefixParam';
            originalOpportunityNamePrefixParam = originalOpportunityNamePrefix + '%';
        }
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Contract> scope) {
        evaluatedCount += scope.size();

        /*
         * RenewalAPI.renewContracts() takes a list but is not documented to isolate failures
         * within it - a bad record could throw for the whole call. Renewing one Contract at a
         * time keeps a single failure from blocking the rest of this chunk (same per-record
         * isolation principle as EditionRenewalOpportunityBatch's insertPartial pattern).
         */
        for (Contract c : scope) {
            Savepoint sp = Database.setSavepoint();
            try {
                SBQQ.RenewalAPI.renewContracts(new List<Contract>{ c }, null);
                renewedCount++;
            } catch (Exception ex) {
                Database.rollback(sp);
                failedCount++;
                String detail = 'Renewal failed for Contract ' + c.Id + ' (Order ' + c.SBQQ__Order__c + '): ' + ex.getMessage();
                failureDetails.add(detail);
                Flow_Log__c errorLog = new Flow_Log__c();
                errorLog.Class_Name__c = 'ContractRenewalApiBatch';
                errorLog.Error_Description__c = detail;
                errorLog.Record_Name__c = 'RecordId: ' + c.Id;
                insert errorLog;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Renewal_Run__c run = new Renewal_Run__c(Id = runId);
        run.End_Time__c = Datetime.now();
        run.Records_Evaluated__c = evaluatedCount;
        run.Renewals_Created__c = renewedCount;
        run.Records_Skipped__c = 0;
        run.Records_Failed__c = failedCount;
        run.Failure_Detail__c = String.join(failureDetails, '\n');
        run.Status__c = failedCount > 0 ? 'Completed with Errors' : 'Completed';
        update run;
    }
}
