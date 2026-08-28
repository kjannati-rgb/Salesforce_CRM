trigger OpportunityTrigger on Opportunity (after insert,after update,before insert, before update) {
    if(trigger.isafter && trigger.isupdate){
        OpportunityTriggerHandler.handleAfterInsertUpdate(Trigger.new);
        OpportunityAnalyticsCreate.createRecords(Trigger.new);
    }
    // if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
    //   OpportunityBillingEntityHandler.evaluate(Trigger.new, Trigger.oldMap);
    //}
    if (Trigger.isAfter && (Trigger.isUpdate || Trigger.isInsert)) {
        OpportunityHandler.LockOppRecords(Trigger.new, Trigger.oldMap);
        OpportunityChangePublisher.publishFor(Trigger.new,
                                              Trigger.isInsert ? null : Trigger.oldMap,
                                              Trigger.isInsert,
                                              Trigger.isUpdate);
    }
    
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        OpportunityBillingEntityHandler.evaluate(Trigger.new, Trigger.oldMap);
    }
}