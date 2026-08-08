trigger OpportunityTrigger on Opportunity (after insert, after update, before insert, before update, after delete, after undelete) {
    if(trigger.isafter && trigger.isupdate){
        OpportunityTriggerHandler.handleAfterInsertUpdate(Trigger.new);
        OpportunityAnalyticsCreate.createRecords(Trigger.new);
    }
   // if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
     //   OpportunityBillingEntityHandler.evaluate(Trigger.new, Trigger.oldMap);
    //}

    // FSS — firm USD rollups (enqueue affected firms on relevant change / ins / del / undel)
    if (Trigger.isAfter) {
        if (Trigger.isDelete) {
            OpportunityFirmRollupHelper.handle(null, Trigger.oldMap, true);
        } else if (Trigger.isInsert || Trigger.isUndelete) {
            OpportunityFirmRollupHelper.handle(Trigger.new, null, false);
        } else if (Trigger.isUpdate) {
            OpportunityFirmRollupHelper.handle(Trigger.new, Trigger.oldMap, false);
        }
    }
}
