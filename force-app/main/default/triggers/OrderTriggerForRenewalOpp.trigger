trigger OrderTriggerForRenewalOpp on Order (after Update ) {

    if(trigger.IsUpdate && Trigger.IsAfter) {

        Map<Id, Id> OwnerIdBYoppoId = new Map<Id, Id>();
        Map<Id, Id> OrderIdBYoppoId = new Map<Id, Id>();
        Map<Id, Id> reducedOrderIdBYoppoId=new Map<Id, Id>();
        Set<Id> oppIds = new Set<Id>();

        for(Order newOrder: Trigger.new){
            Order oldOrder = Trigger.oldMap.get(newOrder.ID);

            System.debug('--------------------------------------------------------------------------');
            System.debug('newOrder.Status'+newOrder.Status);
            System.debug('oldOrder.Status'+oldOrder.Status);

            System.debug('newOrder.Id'+newOrder);
            System.debug('oldOrder.Id'+oldOrder);

                if(newOrder.Status != oldOrder.Status && newOrder.Status == 'Activated' && newOrder.OpportunityId != null && newOrder.IsReductionOrder!= True && newOrder.Type!='Amendment'){
                    System.debug('newOrder.Status'+newOrder.Status);
                    System.debug('oldOrder.Status'+oldOrder.Status);
                    oppIds.add(newOrder.OpportunityId);
                    OwnerIdBYoppoId.put(newOrder.OpportunityId, newOrder.id);
                    OrderIdBYoppoId.put(newOrder.OpportunityId,newOrder.id);
                }
                Else if(newOrder.Status != oldOrder.Status && newOrder.Status == 'Activated' &&  newOrder.IsReductionOrder){
                    System.debug('--------------------------------------------------------------------------');
                    System.debug('newOrder.Status'+newOrder.Status);
                    System.debug('oldOrder.Status'+oldOrder.Status);
                    reducedOrderIdBYoppoId.put(newOrder.OriginalOrderId,newOrder.id);
                    System.debug('reducedOrderIdBYoppoId'+reducedOrderIdBYoppoId);
                }

        }
        // to get user info or org default value
        Trigger_Settings__c app=Trigger_Settings__c.getValues(Userinfo.getProfileId())!=null?Trigger_Settings__c.getValues(Userinfo.getProfileId()):Trigger_Settings__c.getOrgDefaults();
        system.debug('app'+app);

            if(!oppIds.isEmpty() && (app != null && app.Is_Active__c && app.Trigger_Name__c=='OrderTriggerForRenewalOpp')) {
                /*
                 * Enqueued instead of calling an @future method directly (fixes D4/D5).
                 * Each trigger invocation (each chunk of a bulk order-activation transaction)
                 * gets its own queueable job, so nothing past the first 200 records in a
                 * bulk update gets silently dropped, and this is safe to call even if the
                 * DML that fired this trigger is itself already running inside a future,
                 * batch, or another queueable's execute context.
                 */
                System.enqueueJob(new RenewalOpportunityQueueable(OwnerIdBYoppoId, OrderIdBYoppoId));
            }

            if(!reducedOrderIdBYoppoId.isEmpty() && (app != null && app.Is_Active__c)) {
                System.debug('Trigger line 44'+reducedOrderIdBYoppoId);

                system.debug('reducedOrderIdBYoppoId'+reducedOrderIdBYoppoId);
                RenewalOpportunityHandler2.deleteReducedOrderOpportunity(reducedOrderIdBYoppoId);

            }

    }

}
