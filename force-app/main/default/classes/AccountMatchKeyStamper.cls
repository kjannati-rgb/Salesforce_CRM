/**
 * AccountMatchKeyStamper
 * ----------------------
 * Keeps the Smart Convert match keys alive on NEWLY created Firm/Office accounts.
 * The one-off backfill keyed existing accounts; without this, every manually created
 * or data-loaded account is invisible to the matcher until someone hand-fills the
 * domain. Called by the record-triggered flow Account_Stamp_Match_Keys on create.
 *
 * Derives Match_Domain__c from Website (free-mail-safe, same rule as the backfill)
 * and Match_Name__c from Name. Only ever fills blanks — never overwrites a key a
 * human or the backfill already set. Bulk-safe: one query, one update per batch.
 */
public with sharing class AccountMatchKeyStamper {

    @InvocableMethod(label='Stamp Account Match Keys'
                     description='Derive Match_Domain__c (from Website) and Match_Name__c (from Name) when blank.')
    public static void stamp(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;
        List<Account> toUpdate = new List<Account>();
        for (Account a : [SELECT Id, Name, Website, Match_Domain__c, Match_Name__c
                          FROM Account WHERE Id IN :accountIds]) {
            Boolean changed = false;
            if (String.isBlank(a.Match_Domain__c) && String.isNotBlank(a.Website)) {
                String dom = LeadMatchSelectService.domainKey(null, a.Website);
                if (String.isNotBlank(dom)) { a.Match_Domain__c = dom; changed = true; }
            }
            if (String.isBlank(a.Match_Name__c) && String.isNotBlank(a.Name)) {
                String nm = MatchDomainBackfill.normalizeFirmName(a.Name);
                if (String.isNotBlank(nm)) { a.Match_Name__c = nm; changed = true; }
            }
            if (changed) toUpdate.add(a);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}
