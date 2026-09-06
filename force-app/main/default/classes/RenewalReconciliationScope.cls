/**
 * Filter criteria for RenewalReconciliationBatch. The same scope shape drives both the
 * one-off FY26 backfill (a date range and a brand) and the ongoing nightly run (no filters
 * at all, or a rolling date window) - there is no separate backfill-only code path.
 */
public class RenewalReconciliationScope {

    public Date activatedFrom;
    public Date activatedTo;
    public Set<String> brands;
    public Set<String> productFamilies;
    public Set<Id> accountIds;
    public Boolean dryRun;

    public RenewalReconciliationScope() {
        this.dryRun = false;
    }

    /**
     * @return a short human-readable summary of this scope, for the Renewal_Run__c
     *         Scope Description field
     */
    public String describe() {
        List<String> parts = new List<String>();
        if (activatedFrom != null || activatedTo != null) {
            parts.add('activated ' + (activatedFrom != null ? String.valueOf(activatedFrom) : '(any)')
                + ' to ' + (activatedTo != null ? String.valueOf(activatedTo) : '(any)'));
        }
        if (brands != null && !brands.isEmpty()) {
            parts.add('brands: ' + String.join(new List<String>(brands), ', '));
        }
        if (productFamilies != null && !productFamilies.isEmpty()) {
            parts.add('families: ' + String.join(new List<String>(productFamilies), ', '));
        }
        if (accountIds != null && !accountIds.isEmpty()) {
            parts.add(accountIds.size() + ' account(s)');
        }
        if (parts.isEmpty()) {
            parts.add('unscoped (all activated orders)');
        }
        if (dryRun) {
            parts.add('DRY RUN');
        }
        return String.join(parts, '; ');
    }

    /**
     * @return this scope serialized as JSON, for the Renewal_Run__c Scope Parameters
     *         field (audit trail of exactly what filters a given run used)
     */
    public String toJson() {
        return JSON.serialize(this);
    }
}
