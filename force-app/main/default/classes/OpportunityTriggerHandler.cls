public class OpportunityTriggerHandler {
    
    public static void handleAfterInsertUpdate(List<Opportunity> newOpps) {
        if (newOpps == null || newOpps.isEmpty()) {
            return;
        }
        
        // Collect Opportunity IDs from trigger records
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            if (opp.Id != null) {
                oppIds.add(opp.Id);
            }
        }
        
        if (!oppIds.isEmpty()) {
            // Call async processing future method
            system.debug('calling async method');
            ProcessLineItems.updateDealYears(new List<Id>(oppIds));
        }
    }
}