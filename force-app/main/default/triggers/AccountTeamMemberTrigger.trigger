/**
 * Delegates to AccountTeamMemberTriggerHandler, which enforces the single-holder
 * guardrail, writes the Account_Team_Change__c audit trail, and keeps the
 * reportable Account CSM mirror fields in sync - for every entry point, not just
 * the Account Team Manager LWC. See the handler for detail and bypass behaviour.
 */
trigger AccountTeamMemberTrigger on AccountTeamMember (
        before insert, before update,
        after insert, after update, after delete, after undelete) {
    AccountTeamMemberTriggerHandler.run();
}
