// Schedule the hourly sweep (idempotent: abort existing job of same name first)
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'PFC Routing SLA Sweep']) {
    System.abortJob(ct.Id);
}
String jobId = System.schedule('PFC Routing SLA Sweep', '0 0 * * * ?', new PFCRoutingSlaSweepSchedulable());
System.debug('SCHEDULED: ' + jobId);

// Clean up the 3 sweep-test PFCs
List<Pardot_Form_Completion__c> leftovers = [
    SELECT Id FROM Pardot_Form_Completion__c WHERE Form_Name__c LIKE 'Bulk Cockpit %'
];
delete leftovers;
System.debug('DELETED_TEST_PFCS: ' + leftovers.size());

// Confirm no automation faults today
System.debug('FLOW_LOG_TODAY: ' + [SELECT COUNT() FROM Flow_Log__c WHERE CreatedDate = TODAY AND Flow_Name__c LIKE 'PFC%']);
