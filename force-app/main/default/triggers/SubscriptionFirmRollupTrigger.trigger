trigger SubscriptionFirmRollupTrigger on SBQQ__Subscription__c (after insert, after update, after delete, after undelete) {
    // FSS — firm active-subscription rollups
    if (Trigger.isDelete) {
        SubscriptionFirmRollupHelper.handle(null, Trigger.oldMap, true);
    } else if (Trigger.isInsert || Trigger.isUndelete) {
        SubscriptionFirmRollupHelper.handle(Trigger.new, null, false);
    } else if (Trigger.isUpdate) {
        SubscriptionFirmRollupHelper.handle(Trigger.new, Trigger.oldMap, false);
    }
}
