// Gate B bulk test: 200 Pardot-style Tasks in one DML -> 200 queue-owned PFCs
List<Task> tasks = new List<Task>();
for (Integer i = 0; i < 200; i++) {
    tasks.add(new Task(Subject = 'PFC: Bulk Cockpit ' + i, Status = 'Completed', Priority = 'Normal', ActivityDate = Date.today()));
}
insert tasks;

List<Pardot_Form_Completion__c> pfcs = [
    SELECT Id, OwnerId, Sales_Rep__c FROM Pardot_Form_Completion__c WHERE Form_Name__c LIKE 'Bulk Cockpit %'
];
System.assertEquals(200, pfcs.size(), 'BULK FAIL: expected 200 PFCs, got ' + pfcs.size());
Integer queueOwned = 0;
for (Pardot_Form_Completion__c p : pfcs) {
    if (String.valueOf(p.OwnerId).startsWith('00G') && p.Sales_Rep__c == null) queueOwned++;
}
System.assertEquals(200, queueOwned, 'BULK FAIL: not all queue-owned/rep-blank');
System.debug('BULK_200_PASS queueOwned=' + queueOwned);

// leave 3 records for the sweep E2E test; clean the rest
List<Pardot_Form_Completion__c> toDelete = new List<Pardot_Form_Completion__c>();
for (Integer i = 3; i < pfcs.size(); i++) toDelete.add(pfcs[i]);
delete toDelete;
delete tasks;
System.debug('CLEANUP_DONE kept=3');
