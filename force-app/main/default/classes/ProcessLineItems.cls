public class ProcessLineItems implements Queueable {

    // Opportunity ids already dispatched this transaction — CPQ and the flow chain
    // re-save the same Opportunity several times per commit; repeat saves enqueue nothing.
    @TestVisible
    private static Set<Id> processedOppIds = new Set<Id>();

    private List<Id> opportunityIds;

    public ProcessLineItems(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

    public void execute(QueueableContext context) {
        recalculateDealYears(opportunityIds);
    }

    // Entry point from OpportunityTriggerHandler. Moves the line-item query and its DML
    // cascade (the whole OLI trigger stack) off the synchronous save path.
    public static void updateDealYears(List<Id> opps) {
        if (opps == null || opps.isEmpty()) {
            return;
        }

        List<Id> toProcess = new List<Id>();
        for (Id oppId : opps) {
            if (oppId != null && !processedOppIds.contains(oppId)) {
                processedOppIds.add(oppId);
                toProcess.add(oppId);
            }
        }
        if (toProcess.isEmpty()) {
            return;
        }

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ProcessLineItems(toProcess));
        } else {
            // Queueable budget exhausted (e.g. invoked from another async context) —
            // fall back to running inline, as this method always did before.
            recalculateDealYears(toProcess);
        }
    }

    public static void recalculateDealYears(List<Id> opps) {
        Set<Id> opportunityIds = new Set<Id>();
        opportunityIds.addAll(opps);

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        // Query all relevant OpportunityLineItems
        List<OpportunityLineItem> oliList = [
            SELECT Id, Deal_Start_Year__c, Deal_End_Year__c, Product2.Publication_Title__c, Product2.Financial_Year__c,Product2.Clean_Product_Code__c
            FROM OpportunityLineItem
            WHERE Product2.Financial_Year__c != null
              AND Product2.Subscription_Model__c = 'Edition-Based'
              AND OpportunityId IN :opportunityIds
        ];

        if (oliList.isEmpty()) {
            System.debug('No relevant OpportunityLineItems found. Skipping update.');
            return;
        }

        // Map to hold publication edition to all financial years found
        Map<String, List<Integer>> editionToYears = new Map<String, List<Integer>>();

        for (OpportunityLineItem oli : oliList) {
            String edition = oli.Product2.Clean_Product_Code__c.left(9);
            Integer fy = Integer.valueOf(String.valueOf(oli.Product2.Financial_Year__c));

            if (edition == null) {
                continue; // Skip if edition is null
            }

            if (!editionToYears.containsKey(edition)) {
                editionToYears.put(edition, new List<Integer>());
            }
            editionToYears.get(edition).add(fy);
        }

        // Calculate min and max financial years per publication edition
        Map<String, Integer> editionMinYear = new Map<String, Integer>();
        Map<String, Integer> editionMaxYear = new Map<String, Integer>();

        for (String edition : editionToYears.keySet()) {
            List<Integer> years = editionToYears.get(edition);
            years.sort();
            editionMinYear.put(edition, years[0]);
            editionMaxYear.put(edition, years[years.size() - 1]);
        }

        // Prepare list of line items to update only if values have changed
        List<OpportunityLineItem> oliToUpdate = new List<OpportunityLineItem>();
        for (OpportunityLineItem oli : oliList) {
            String edition = oli.Product2.Clean_Product_Code__c.left(9);
            String newStartYear = String.valueOf(editionMinYear.get(edition));
            String newEndYear = String.valueOf(editionMaxYear.get(edition));

            Boolean hasChanged = false;

            if (oli.Deal_Start_Year__c != newStartYear) {
                oli.Deal_Start_Year__c = newStartYear;
                hasChanged = true;
            }

            if (oli.Deal_End_Year__c != newEndYear) {
                oli.Deal_End_Year__c = newEndYear;
                hasChanged = true;
            }

            if (hasChanged) {
                oliToUpdate.add(oli);
            }
        }

        if (!oliToUpdate.isEmpty()) {
            System.debug('Updating ' + oliToUpdate.size() + ' OpportunityLineItems with new deal years');
            update oliToUpdate;
            system.debug('Updated line items '+ oliToUpdate);
        } else {
            System.debug('No OpportunityLineItems required update.');
        }
    }
}
