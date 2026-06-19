/**
 * One-time data migration for the attorney-field consolidation.
 * Copies Account.of_Attorneys__c (retire) into Number_of_Attorneys__c (survivor)
 * wherever they differ - covering both survivor-blank and conflict records
 * (RETIRE-wins tie-break). Runs in system mode (bypasses FLS) and chunks via
 * Batch Apex to clear the 10k synchronous DML limit.
 *
 * Uses dynamic SOQL + dynamic field access so the class has NO compile-time
 * dependency on of_Attorneys__c and will still compile after the field is deleted.
 */
public class AttorneyCountMigrationBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, of_Attorneys__c, Number_of_Attorneys__c FROM Account WHERE of_Attorneys__c != null'
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Account> toUpdate = new List<Account>();
        for (SObject s : scope) {
            Object retire = s.get('of_Attorneys__c');
            Object surv   = s.get('Number_of_Attorneys__c');
            if (retire != null && retire != surv) {
                Account u = new Account(Id = (Id) s.get('Id'));
                u.put('Number_of_Attorneys__c', retire);
                toUpdate.add(u);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false); // allOrNone=false: isolate per-record failures
        }
    }

    public void finish(Database.BatchableContext bc) {}
}
