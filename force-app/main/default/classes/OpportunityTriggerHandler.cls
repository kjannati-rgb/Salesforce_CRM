public class OpportunityTriggerHandler {

    public static void handleAfterInsertUpdate(List<Opportunity> newOpps) {
        if (newOpps == null || newOpps.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> oldMap = Trigger.isExecuting
            ? (Map<Id, Opportunity>) Trigger.oldMap
            : null;

        // The deal-years recalc derives entirely from line items (Product2 Financial_Year /
        // Clean_Product_Code on Edition-Based lines). Line-set changes surface on the
        // Opportunity as a No_of_Line_Items__c (roll-up summary) or Amount change, which
        // system-fires this trigger — so only those saves need to dispatch the recalc.
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            if (opp.Id == null || opp.HasOpportunityLineItem != true) {
                continue; // no line items — nothing for the recalc to read
            }
            if (oldMap != null && oldMap.containsKey(opp.Id)) {
                Opportunity oldOpp = oldMap.get(opp.Id);
                Boolean lineSetChanged = oldOpp.No_of_Line_Items__c != opp.No_of_Line_Items__c
                    || oldOpp.Amount != opp.Amount;
                if (!lineSetChanged) {
                    continue;
                }
            }
            oppIds.add(opp.Id);
        }

        if (!oppIds.isEmpty()) {
            // Dispatch async processing (Queueable; deduplicated per transaction)
            ProcessLineItems.updateDealYears(new List<Id>(oppIds));
        }
    }
}
