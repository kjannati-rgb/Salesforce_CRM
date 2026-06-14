# Centellic — Stabilise work: split production deployment runbook
### Two deployments by risk · LBR_PROD `00D6g0000081IOgEAM` · drafted 13 Jun 2026

The Stabilise work splits cleanly into a **low-risk inert foundation** and a **high-blast-radius
behaviour change**. Deploy them separately, on different risk tracks. Built & verified in KJDEV.

> **Pre-flight name-collision check — DONE (13 Jun):** prod's only `TestDataFactory` / `TriggerHandler`
> classes are MANAGED-package (namespaces LID, echosign_dev1, trumpet, DaScoopComposer, bvd_connector, pi),
> which are namespace-isolated from unmanaged code. Our unmanaged versions are net-new — **no overwrite.**
> (Re-run before deploy: `SELECT Name, NamespacePrefix FROM ApexClass WHERE Name IN ('TestDataFactory','TriggerHandler','Platform_Fault_Logger')`.)

---

## DEPLOYMENT 1 — Inert foundation (LOW RISK, deploy freely)

**Why low risk:** every component is additive, inert until used, fail-open, or test-only. Nothing
changes a production runtime path on arrival.

| Component | Type | Risk note |
|---|---|---|
| `Platform_Fault_Logger` | Flow (autolaunched subflow) | net-new; does nothing unless a flow calls it; fail-open |
| `Fault_Alert_Setting__mdt` + `Default` record | CMDT | net-new; `Alert_Enabled__c = false` → behaviour-neutral |
| `TriggerHandler` + `OppTriggerHandlerReference` + `TriggerHandler_Test` | Apex | net-new unmanaged; not wired to any trigger |
| `TestDataFactory` + `TestDataFactory_Test` | Apex (`@isTest`) | never runs in a prod transaction |
| `Opportunity_AfterSave_Orchestrator` | Flow (Draft) | inert reference; not active |
| `REV71_ALM_Code_Faults` list view + report + folder | reports/UI | read-only |
| Fixed test classes (`OpportunityBillingEntityBatch_Test`, `TestALMSplitLineItemBatch`, etc.) | Apex `@isTest` | improvements; raise coverage |

**Command (validate first):**
```bash
sf project deploy start \
  -m "Flow:Platform_Fault_Logger" \
  -m "CustomObject:Fault_Alert_Setting__mdt" -m "CustomMetadata:Fault_Alert_Setting.Default" \
  -m "ApexClass:TriggerHandler" -m "ApexClass:OppTriggerHandlerReference" -m "ApexClass:TriggerHandler_Test" \
  -m "ApexClass:TestDataFactory" -m "ApexClass:TestDataFactory_Test" \
  -m "ListView:Flow_Log__c.REV71_ALM_Code_Faults" \
  -o LBR_PROD --test-level RunSpecifiedTests \
  --tests TriggerHandler_Test --tests TestDataFactory_Test \
  --dry-run    # then re-run without --dry-run
```
- [ ] Validation green (incl. the 2 named tests). **Use RunSpecifiedTests** — prod has pre-existing red tests; RunLocalTests would fail the deploy on unrelated failures.
- [ ] FLS for the Fault_Alert_Setting fields if any profile needs read (admin only by default).
- [ ] Deploy the Flow_Log report + folder separately (the report needs a one-time UI re-save of the `PFC_Flow_Logs` report type to bind — known metadata quirk).
- [ ] After deploy: confirm `Platform_Fault_Logger` is Active and `Fault_Alert_Setting.Default.Alert_Enabled__c = false`.

**Rollback:** these are additive — nothing to roll back; if needed, deactivate/delete the new components. No existing prod behaviour was touched.

---

## DEPLOYMENT 2 — Master-flow fault handling (HIGH BLAST RADIUS, controlled change)

**What it is:** adds fault paths to 8 elements (6 approval/email actions + 2 record updates) of the
`Opportunity` flow (label `Opportunity_AfterUpdate_MasterFlow`), routing faults to `Platform_Fault_Logger`
so the save completes-and-logs instead of throwing an unhandled fault. **Deployment 1 must land first**
(this flow references `Platform_Fault_Logger`).

### Risks (read before scheduling)
1. **Behaviour change — approvals.** Previously a failed approval submit aborted the whole save (loud/blocking);
   now it logs and the save proceeds. A deal could be saved without its Finance/Cancellation approval submitted.
   → **Requires finance/approvals stakeholder sign-off.**
2. **Blast radius = every Opportunity save.** A defect here fails all Opportunity saves. → staged activation + tested rollback, not fire-and-forget.
3. **Partial fix.** Only 8 of 25 elements are guarded; the 17 SUBFLOWS (incl. Customer Journey) still throw
   unhandled faults (Flow doesn't allow fault paths on subflow calls). This reduces — does not eliminate —
   master-flow faults. Confirm via Flow_Log after go-live which faults remain.
4. **Authoring method.** The 8 fault paths were added by scripted XML, validated by one test path
   (`OpportunityChangePublisherTest`). → **Open in Flow Builder and visually verify the 8 fault connectors**
   before activating; the flow has 9 decisions / 17 subflows / multiple branches not all exercised.

### Procedure
1. **Diff & review:** retrieve prod `Flow:Opportunity`, diff against this branch's version; open the new
   version in Flow Builder and eyeball each of the 8 fault connectors. *(read-only)*
2. **Deploy as Draft:** `sf project deploy start -m "Flow:Opportunity" -o LBR_PROD` — prod's "deploy flows as
   active" is OFF, so it lands **Draft** (no effect yet). Confirm the prior version (v27) is still the Active one.
3. **Quiet-window activation:** in a low-traffic window, activate the new version (Setup → Flows). Keep the
   prior version handy.
4. **Watch:** monitor `Flow_Log__c` (REV-71 list view) + Opportunity save success for ~1 day. Optionally enable
   `Fault_Alert_Setting.Alert_Enabled__c` with an admin recipient during the soak.
5. **Validate semantics:** confirm with finance that no required approval is being silently skipped (sample
   recent deals that hit the fault path in Flow_Log).

### Rollback (instant)
Setup → Flows → `Opportunity` → **activate the prior version (v27)**. No deploy needed; effect is immediate.
Stamped Flow_Log rows are harmless data.

### Same pattern, later (separate changes)
- `Opportunity_Contact_Role_Check_for_Duplicate` (OCR pilot) — same controlled track; minor behaviour change
  (dup-check skipped if the lookup faults). Lower stakes.
- The 17 subflows each need **internal** fault handling (Customer Journey rebuild is the big one) — future work.

---

## Summary
- **Deployment 1**: ship anytime — low risk, and it's the observability prerequisite for everything else.
- **Deployment 2**: schedule as a reviewed, signed-off, staged change with an instant rollback. Worth it
  (clears the prod live #2 error) but earns the ceremony.
