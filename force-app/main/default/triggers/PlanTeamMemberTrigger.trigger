trigger PlanTeamMemberTrigger on Plan_Team_Member__c (after insert, after update, after delete, after undelete) {
    Set<Id> planIds = new Set<Id>();
    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Plan_Team_Member__c tm : Trigger.new) {
            if (tm.Account_Plan__c != null) planIds.add(tm.Account_Plan__c);
        }
    }
    if (Trigger.isUpdate || Trigger.isDelete) {
        for (Plan_Team_Member__c tm : Trigger.old) {
            if (tm.Account_Plan__c != null) planIds.add(tm.Account_Plan__c);
        }
    }
    PlanSharingService.recalculate(planIds);
}
