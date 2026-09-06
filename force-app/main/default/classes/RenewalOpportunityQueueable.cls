/**
 * Enqueues RenewalOpportunityHandler2.processOpportunities so it runs as a Queueable
 * instead of a future method (fixes D5 - a future method cannot be invoked from an
 * existing async context, which had already failed in production). Queueable also
 * gives each trigger invocation its own job instead of relying on a static runOnce
 * guard that silently dropped chunks past the first 200 records in a bulk activation
 * (fixes D4).
 */
public with sharing class RenewalOpportunityQueueable implements Queueable {

    private final Map<Id, Id> ownerIdByOppId;
    private final Map<Id, Id> orderIdByOppId;

    public RenewalOpportunityQueueable(Map<Id, Id> ownerIdByOppId, Map<Id, Id> orderIdByOppId) {
        this.ownerIdByOppId = ownerIdByOppId;
        this.orderIdByOppId = orderIdByOppId;
    }

    public void execute(QueueableContext context) {
        RenewalOpportunityHandler2.processOpportunities(ownerIdByOppId, orderIdByOppId);
    }
}
