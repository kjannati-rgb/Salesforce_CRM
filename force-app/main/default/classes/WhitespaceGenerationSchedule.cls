/**
 * Scheduled job that regenerates every active Account Plan's white-space matrix daily (architecture §4)
 * — the same real term/pipeline signals that drive the matrix also raise Plan_Signal__c records on
 * transition into In_Renewal/Win_Back (see WhitespaceGenerationService.emitTransitionSignals()).
 * Schedule: System.schedule('Account Plan White-Space Regen', '0 0 3 * * ?', new WhitespaceGenerationSchedule());
 */
public with sharing class WhitespaceGenerationSchedule implements Schedulable {
    public void execute(SchedulableContext sc) {
        Set<Id> ids = new Set<Id>();
        for (Account_Plan__c p : [SELECT Id FROM Account_Plan__c WHERE Plan_Status__c = 'Active']) {
            ids.add(p.Id);
        }
        WhitespaceGenerationService.generate(ids);
    }
}
