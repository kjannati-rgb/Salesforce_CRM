/**
 * OppTriggerHandlerReference — Centellic reference implementation (skeleton).
 *
 * NOTE: named *Reference to avoid colliding with the org's existing
 * OpportunityTriggerHandler. During Phase C the existing custom Opportunity
 * triggers/handlers are consolidated INTO a single handler built to this shape.
 *
 * Target: consolidate the 3 CUSTOM Opportunity triggers (OpportunityTrigger,
 * Ast_OpportunityTrigger, OpportunityTriggerMBLChangeEvent) into one handler.
 * The 5 MANAGED triggers (CPQ/SBQQ, Advanced Approvals/sbaa, ZoomInfo/DOZISF,
 * Rollup Helper/RHX, trumpet) are vendor-owned and stay untouched.
 *
 * Each concern maps to a method ported from a legacy trigger/flow during
 * migration (see Centellic_Automation_Standard_and_Opportunity_Reference.md §9).
 * Stubs here establish the SHAPE; logic is ported one concern at a time, each
 * with its own test, behind the framework's bypass.
 */
public with sharing class OppTriggerHandlerReference extends TriggerHandler {

    private List<Opportunity> newList;
    private Map<Id, Opportunity> oldMap;

    public OppTriggerHandlerReference() {
        this.newList = (List<Opportunity>) Trigger.new;
        this.oldMap  = (Map<Id, Opportunity>) Trigger.oldMap;
    }

    protected override void beforeInsert() {
        // PORT: same-record defaulting/stamping (Opportunity_BeforeSaveFlow +
        //       Update_Opportunity_Contract_Attached_Field + UltimateAccountBeforeSaving).
    }

    protected override void beforeUpdate() {
        // PORT: before-update validations (Complete_Customer_Success_Task_validation, etc.)
    }

    protected override void afterInsert() {
        // PORT: cross-object after-save work (Opportunity generic flow, Customer_Journey rebuild,
        //       notifications). Heavy/bulk logic belongs here; simple field work stays in the
        //       before-save orchestrator flow.
    }

    protected override void afterUpdate() {
        // PORT: after-update cross-object work + notifications.
    }
}
