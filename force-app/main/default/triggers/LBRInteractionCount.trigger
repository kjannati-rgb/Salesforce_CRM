/**
 * LBRInteractionCount
 * -------------------
 * Keeps Contact.Count_of_LBR_Interactions__c in sync after Contact__c was converted from
 * Master-Detail to Lookup (REV-68), since a Lookup cannot carry a roll-up summary.
 */
trigger LBRInteractionCount on LBR_Interactions__c (after insert, after update, after delete, after undelete) {
    LBRInteractionCountHandler.handle(Trigger.new, Trigger.oldMap);
}
