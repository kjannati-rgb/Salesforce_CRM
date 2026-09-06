/**
 * Reconciles activated orders against renewal opportunities. Expresses one invariant:
 * every activated order whose primary quote has a renewal-eligible line, and which has
 * no downstream renewal opportunity yet, gets one.
 *
 * This is the permanent fix and the backfill tool in one class, not two - the nightly
 * scheduled run and the FY26 backfill differ only in the RenewalReconciliationScope
 * passed to the constructor. Both call RenewalOpportunityHandler2.processOpportunities,
 * the same engine the real-time OrderTriggerForRenewalOpp trigger calls, so there is
 * exactly one code path that actually creates a renewal.
 *
 * Idempotent: the start() query excludes any order whose opportunity already has a
 * downstream renewal (Previous_Opportunity__c), so re-running creates nothing new.
 * Set-based: Database.Batchable chunks natively, no 200-record boundary and no static
 * re-entrancy guard.
 *
 * Known limitation: an order can still finish this run with a renewal Opportunity that
 * has zero quote lines, if its only eligible line's product is missing a
 * SBQQ__RenewalProduct__c mapping. That is a catalogue data-quality gap (see Phase 6),
 * not a bug in this class or in RenewalOpportunityHandler2 - it is not currently broken
 * out as its own reason category here; Failure_Detail__c and a manual check of quote
 * line counts on the run's renewals is the way to spot it until the gap list exists.
 */
public with sharing class RenewalReconciliationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final RenewalReconciliationScope scope;
    private Renewal_Run__c run;

    private Integer evaluatedCount = 0;
    private Integer createdCount = 0;
    private Integer skippedCount = 0;
    private Integer failedCount = 0;
    private Map<String, Integer> skipReasonCounts = new Map<String, Integer>();
    private List<String> failureLines = new List<String>();

    public RenewalReconciliationBatch(RenewalReconciliationScope scope) {
        this.scope = scope != null ? scope : new RenewalReconciliationScope();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        run = new Renewal_Run__c(
            Scope_Description__c = scope.describe(),
            Scope_Parameters__c = scope.toJson(),
            Dry_Run__c = scope.dryRun,
            Start_Time__c = Datetime.now(),
            Status__c = 'Running');
        insert run;

        List<String> orderConditions = new List<String>{
            'Status = \'Activated\'', 'OpportunityId != null', 'IsReductionOrder != true', 'Type != \'Amendment\''
        };
        Date activatedFrom = scope.activatedFrom;
        Date activatedTo = scope.activatedTo;
        Set<Id> accountIds = scope.accountIds;
        if (activatedFrom != null) {
            orderConditions.add('ActivatedDate >= :activatedFrom');
        }
        if (activatedTo != null) {
            orderConditions.add('ActivatedDate <= :activatedTo');
        }
        if (accountIds != null && !accountIds.isEmpty()) {
            orderConditions.add('AccountId IN :accountIds');
        }

        Map<Id, Id> opportunityIdByOrderId = new Map<Id, Id>();
        for (Order o : Database.query(
            'SELECT Id, OpportunityId FROM Order WHERE ' + String.join(orderConditions, ' AND ')
        )) {
            opportunityIdByOrderId.put(o.Id, o.OpportunityId);
        }
        Set<Id> allScopedOpportunityIds = new Set<Id>(opportunityIdByOrderId.values());
        evaluatedCount = opportunityIdByOrderId.size();

        List<String> qlConditions = new List<String>{
            'SBQQ__Quote__r.SBQQ__Primary__c = true',
            'SBQQ__Quote__r.SBQQ__Opportunity2__c IN :allScopedOpportunityIds',
            'SBQQ__Product__r.Renewal_Not_Required__c = false'
        };
        Set<String> brands = scope.brands;
        Set<String> productFamilies = scope.productFamilies;
        if (brands != null && !brands.isEmpty()) {
            qlConditions.add('SBQQ__Product__r.Brand__c IN :brands');
        }
        if (productFamilies != null && !productFamilies.isEmpty()) {
            qlConditions.add('SBQQ__Product__r.Family IN :productFamilies');
        }

        Set<Id> eligibleOpportunityIds = new Set<Id>();
        for (SBQQ__QuoteLine__c ql : Database.query(
            'SELECT SBQQ__Quote__r.SBQQ__Opportunity2__c FROM SBQQ__QuoteLine__c WHERE ' + String.join(qlConditions, ' AND ')
        )) {
            eligibleOpportunityIds.add(ql.SBQQ__Quote__r.SBQQ__Opportunity2__c);
        }

        Integer noEligibleLineCount = 0;
        for (Id oppId : allScopedOpportunityIds) {
            if (!eligibleOpportunityIds.contains(oppId)) {
                noEligibleLineCount++;
            }
        }

        Set<Id> alreadyRenewedOpportunityIds = new Set<Id>();
        for (Opportunity o : [
            SELECT Previous_Opportunity__c FROM Opportunity
            WHERE Previous_Opportunity__c IN :eligibleOpportunityIds
        ]) {
            alreadyRenewedOpportunityIds.add(o.Previous_Opportunity__c);
        }

        skipReasonCounts.put('No renewal-eligible line', noEligibleLineCount);
        skipReasonCounts.put('Already has a renewal', alreadyRenewedOpportunityIds.size());
        skippedCount = noEligibleLineCount + alreadyRenewedOpportunityIds.size();

        Set<Id> targetOpportunityIds = new Set<Id>(eligibleOpportunityIds);
        targetOpportunityIds.removeAll(alreadyRenewedOpportunityIds);

        Set<Id> targetOrderIds = new Set<Id>();
        for (Id orderId : opportunityIdByOrderId.keySet()) {
            if (targetOpportunityIds.contains(opportunityIdByOrderId.get(orderId))) {
                targetOrderIds.add(orderId);
            }
        }

        return Database.getQueryLocator([
            SELECT Id, OpportunityId, AccountId FROM Order WHERE Id IN :targetOrderIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Order> scopeOrders) {
        if (scopeOrders.isEmpty()) {
            return;
        }

        Map<Id, Id> ownerIdByOppId = new Map<Id, Id>();
        Map<Id, Id> orderIdByOppId = new Map<Id, Id>();
        Map<Id, Id> orderIdByOpportunityId = new Map<Id, Id>();
        Set<Id> chunkOpportunityIds = new Set<Id>();

        for (Order o : scopeOrders) {
            chunkOpportunityIds.add(o.OpportunityId);
            orderIdByOpportunityId.put(o.OpportunityId, o.Id);
            ownerIdByOppId.put(o.OpportunityId, o.Id);
            orderIdByOppId.put(o.OpportunityId, o.Id);
        }

        if (scope.dryRun) {
            createdCount += scopeOrders.size();
            return;
        }

        RenewalOpportunityHandler2.processOpportunities(ownerIdByOppId, orderIdByOppId);

        Set<Id> renewedOppIds = new Set<Id>();
        for (Opportunity renewed : [
            SELECT Previous_Opportunity__c FROM Opportunity
            WHERE Previous_Opportunity__c IN :chunkOpportunityIds
        ]) {
            renewedOppIds.add(renewed.Previous_Opportunity__c);
        }
        createdCount += renewedOppIds.size();

        Set<Id> notRenewedOrderIds = new Set<Id>();
        for (Id oppId : chunkOpportunityIds) {
            if (!renewedOppIds.contains(oppId)) {
                notRenewedOrderIds.add(orderIdByOpportunityId.get(oppId));
            }
        }
        if (notRenewedOrderIds.isEmpty()) {
            return;
        }

        failedCount += notRenewedOrderIds.size();
        Map<Id, String> errorByOrderId = new Map<Id, String>();
        for (Flow_Log__c log : [
            SELECT Record_Name__c, Error_Description__c FROM Flow_Log__c
            WHERE Class_Name__c = 'RenewalOpportunityHandler2' AND CreatedDate = TODAY
        ]) {
            if (String.isBlank(log.Record_Name__c)) {
                continue;
            }
            for (Id orderId : notRenewedOrderIds) {
                if (log.Record_Name__c.contains(String.valueOf(orderId))) {
                    errorByOrderId.put(orderId, log.Error_Description__c);
                }
            }
        }
        for (Id orderId : notRenewedOrderIds) {
            String reason = errorByOrderId.containsKey(orderId)
                ? errorByOrderId.get(orderId)
                : 'no renewal produced, no matching Flow_Log__c entry found';
            failureLines.add(orderId + ': ' + reason);
        }
    }

    public void finish(Database.BatchableContext bc) {
        List<String> skipLines = new List<String>();
        for (String reason : skipReasonCounts.keySet()) {
            skipLines.add(reason + ': ' + skipReasonCounts.get(reason));
        }

        run.End_Time__c = Datetime.now();
        run.Records_Evaluated__c = evaluatedCount;
        run.Renewals_Created__c = createdCount;
        run.Records_Skipped__c = skippedCount;
        run.Records_Failed__c = failedCount;
        run.Skip_Reason_Breakdown__c = String.join(skipLines, '\n');
        run.Failure_Detail__c = String.join(failureLines, '\n');
        run.Status__c = failedCount > 0 ? 'Completed with Errors' : 'Completed';
        update run;
    }
}
