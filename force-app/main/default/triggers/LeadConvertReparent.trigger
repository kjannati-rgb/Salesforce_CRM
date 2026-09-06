/**
 * LeadConvertReparent
 * -------------------
 * Immediately re-parents LBR interactions when a Lead is converted (REV-68 follow-up).
 * Delegates to LeadConvertReparentHandler; the nightly sweeper remains the safety net.
 */
trigger LeadConvertReparent on Lead (after update) {
    LeadConvertReparentHandler.handle(Trigger.new, Trigger.oldMap);
}
