/**
 * TriggerHandler — Centellic automation standard, Apex trigger framework.
 *
 * One trigger per object delegates to one handler that extends this base:
 *   trigger OpportunityTrigger on Opportunity (before insert, before update,
 *       after insert, after update, before delete, after delete, after undelete) {
 *       new OpportunityTriggerHandler().run();
 *   }
 *
 * Provides: context dispatch, a recursion guard (max loop count per handler),
 * and a bypass API (per-handler, e.g. for data loads) plus a global kill switch
 * honouring the org-standard Application_Settings__c bypass. No business logic
 * lives here or in the trigger — only in the concrete handler's overrides.
 */
public virtual class TriggerHandler {

    private static Set<String> bypassedHandlers = new Set<String>();
    private static Map<String, Integer> loopCounts = new Map<String, Integer>();
    private Integer maxLoops = 5;
    @TestVisible private String handlerName;

    public TriggerHandler() {
        this.handlerName = String.valueOf(this).split(':')[0];
    }

    /** Entry point called by the trigger. */
    public void run() {
        if (!Trigger.isExecuting) {
            throw new TriggerHandlerException('TriggerHandler.run() called outside trigger context');
        }
        if (!shouldRun()) return;
        addToLoopCount();
        dispatch(Trigger.operationType);
    }

    public void setMaxLoopCount(Integer max) { this.maxLoops = max; }

    // ---- bypass API ----
    public static void bypass(String handler) { bypassedHandlers.add(handler); }
    public static void clearBypass(String handler) { bypassedHandlers.remove(handler); }
    public static Boolean isBypassed(String handler) { return bypassedHandlers.contains(handler); }
    public static void clearAllBypasses() { bypassedHandlers.clear(); }

    // ---- internals (TestVisible so the control logic is provable without a live trigger) ----
    @TestVisible
    private Boolean shouldRun() {
        if (bypassedHandlers.contains(handlerName)) return false;
        if (globalBypassActive()) return false;
        Integer count = loopCounts.get(handlerName);
        if (count != null && count >= maxLoops) return false; // recursion guard
        return true;
    }

    @TestVisible
    private void dispatch(System.TriggerOperation op) {
        switch on op {
            when BEFORE_INSERT { beforeInsert(); }
            when BEFORE_UPDATE { beforeUpdate(); }
            when BEFORE_DELETE { beforeDelete(); }
            when AFTER_INSERT  { afterInsert(); }
            when AFTER_UPDATE  { afterUpdate(); }
            when AFTER_DELETE  { afterDelete(); }
            when AFTER_UNDELETE { afterUndelete(); }
        }
    }

    @TestVisible
    private void addToLoopCount() {
        Integer count = loopCounts.containsKey(handlerName) ? loopCounts.get(handlerName) : 0;
        loopCounts.put(handlerName, count + 1);
    }

    /** Honour the org-standard global automation bypass if present. */
    @TestVisible
    private Boolean globalBypassActive() {
        Application_Settings__c s = Application_Settings__c.getInstance();
        return s != null && s.Disable_Autolaunch_Lightning_Flow__c == true;
    }

    // ---- context hooks: concrete handlers override only what they need ----
    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}

    public class TriggerHandlerException extends Exception {}
}
