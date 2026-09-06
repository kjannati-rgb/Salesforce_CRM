// FULLUAT ops: schedule sweep + Chatter group
List<CronTrigger> existing = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'PFC Routing SLA Sweep'];
if (existing.isEmpty()) {
    System.schedule('PFC Routing SLA Sweep', '0 0 * * * ?', new PFCRoutingSlaSweepSchedulable());
    System.debug('OPS sweep scheduled');
} else {
    System.debug('OPS sweep already scheduled');
}
List<CollaborationGroup> grp = [SELECT Id FROM CollaborationGroup WHERE Name = 'CRM Support'];
if (grp.isEmpty()) {
    insert new CollaborationGroup(Name = 'CRM Support', CollaborationType = 'Public',
        Description = 'PFC routing SLA alerts land here (Triage Cockpit UAT).');
    System.debug('OPS chatter group created');
} else {
    System.debug('OPS chatter group exists');
}
// Cayla must NOT have automation bypassed
List<Application_Settings__c> cayla = [SELECT Id, Disable_Autolaunch_Lightning_Flow__c, Disable_Process_Builders__c, Disable_Validation_Rules__c FROM Application_Settings__c WHERE SetupOwnerId = '005Tm000001WgWcIAK'];
System.debug('OPS cayla bypass rows: ' + cayla);
