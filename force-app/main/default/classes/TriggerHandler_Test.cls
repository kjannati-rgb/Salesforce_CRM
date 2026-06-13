/**
 * Tests for the TriggerHandler framework — proves the control logic (dispatch,
 * recursion guard, bypass API, global bypass, outside-trigger guard) without
 * needing a live trigger. A test-only handler records which contexts fired.
 */
@isTest
private class TriggerHandler_Test {

    /** Test handler: records each context it receives. */
    private class TestHandler extends TriggerHandler {
        public List<String> fired = new List<String>();
        protected override void beforeInsert() { fired.add('BI'); }
        protected override void beforeUpdate() { fired.add('BU'); }
        protected override void afterInsert()  { fired.add('AI'); }
        protected override void afterUpdate()  { fired.add('AU'); }
        protected override void afterDelete()  { fired.add('AD'); }
        protected override void afterUndelete(){ fired.add('AUN'); }
    }

    @isTest
    static void dispatch_routes_each_context() {
        TestHandler h = new TestHandler();
        h.dispatch(System.TriggerOperation.BEFORE_INSERT);
        h.dispatch(System.TriggerOperation.BEFORE_UPDATE);
        h.dispatch(System.TriggerOperation.AFTER_INSERT);
        h.dispatch(System.TriggerOperation.AFTER_UPDATE);
        h.dispatch(System.TriggerOperation.AFTER_DELETE);
        h.dispatch(System.TriggerOperation.AFTER_UNDELETE);
        Assert.areEqual(new List<String>{'BI','BU','AI','AU','AD','AUN'}, h.fired,
            'dispatch must route each operation to its hook in order');
    }

    @isTest
    static void bypass_api_blocks_run() {
        TestHandler h = new TestHandler();
        String name = h.handlerName;
        Assert.isFalse(TriggerHandler.isBypassed(name), 'not bypassed initially');
        TriggerHandler.bypass(name);
        Assert.isTrue(TriggerHandler.isBypassed(name), 'bypass registers');
        Assert.isFalse(h.shouldRun(), 'shouldRun is false when bypassed');
        TriggerHandler.clearBypass(name);
        Assert.isTrue(h.shouldRun(), 'shouldRun true after clearBypass');
        TriggerHandler.bypass(name);
        TriggerHandler.clearAllBypasses();
        Assert.isFalse(TriggerHandler.isBypassed(name), 'clearAllBypasses clears');
    }

    @isTest
    static void recursion_guard_stops_after_max() {
        TestHandler h = new TestHandler();
        h.setMaxLoopCount(2);
        Assert.isTrue(h.shouldRun(), 'run 1 allowed');
        h.addToLoopCount();
        Assert.isTrue(h.shouldRun(), 'run 2 allowed (count=1 < 2)');
        h.addToLoopCount();
        Assert.isFalse(h.shouldRun(), 'run 3 blocked by recursion guard (count=2 >= 2)');
    }

    @isTest
    static void global_bypass_honoured() {
        // org-default Application_Settings__c with the global flow bypass on
        upsert new Application_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true);
        TestHandler h = new TestHandler();
        Assert.isTrue(h.globalBypassActive(), 'global bypass detected from Application_Settings__c');
        Assert.isFalse(h.shouldRun(), 'shouldRun false under global bypass');
    }

    @isTest
    static void run_outside_trigger_throws() {
        try {
            new TestHandler().run();
            Assert.fail('expected TriggerHandlerException outside trigger context');
        } catch (TriggerHandler.TriggerHandlerException e) {
            Assert.isTrue(e.getMessage().contains('outside trigger context'), 'clear message');
        }
    }

    @isTest
    static void opportunity_handler_instantiates() {
        // smoke: the reference handler compiles and constructs (Trigger vars null in test)
        Test.startTest();
        OpportunityTriggerHandler oh = new OpportunityTriggerHandler();
        Test.stopTest();
        Assert.isNotNull(oh, 'reference handler constructs');
    }
}
