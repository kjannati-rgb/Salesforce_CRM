/**
 * REV-60 — Layer 2 invocable wrapper.
 *
 * Apex permits only one @InvocableMethod per class, so the Layer 2 (Opportunity
 * safety-net) entry point lives here while Layer 1 (Quote) stays in
 * ALMPromoDispatchEngine. Both delegate to the same derivation engine.
 */
public without sharing class ALMPromoDispatchOppAction {

    @InvocableMethod(label='REV-60 Stamp ALM Promo/Dispatch — Layer 2 (Opportunity)'
        description='Safety-net: derives & stamps Promo_Code__c / Dispatch_Method_Code__c on the opportunity\'s ALM product lines. CMDT-driven, additive, kill-switchable.')
    public static List<ALMPromoDispatchEngine.FlowResult> stampOpportunity(List<Id> opportunityIds) {
        return ALMPromoDispatchEngine.stampOpportunity(opportunityIds);
    }
}
