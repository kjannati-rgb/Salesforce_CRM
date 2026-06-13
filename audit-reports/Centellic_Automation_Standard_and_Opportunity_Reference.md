# Centellic — Automation Standard & Opportunity Reference Architecture
### The scalable target pattern · companion to the 13 Jun platform diagnostic

This is the standard every object's automation is rebuilt to. It exists so reliability and
maintainability come from **a small number of standardised, observable units** — not from
patching hundreds of flows. The Opportunity worked example (the worst object) is the reference
implementation; every other object follows the same shape.

---

## 1. Principles (non-negotiable)

1. **One Apex trigger per object**, delegating to one handler class via a shared framework. No business logic in the trigger.
2. **One before-save flow + one after-save flow per object** (the "orchestrators"), each calling named subflows for distinct concerns. No other record-triggered flows on the object.
3. **No Workflow Rules, no Process Builder.** Retired into the model.
4. **Config in Custom Metadata**, never hardcoded — environment IDs (queues, record types, users), feature toggles, and per-automation bypass switches.
5. **Every DML / lookup / callout / subflow has a fault path** routed to `Platform_Fault_Logger`. Silent failure is forbidden.
6. **Deterministic order** between the Apex and flow layers, documented per object.
7. **Tested.** No automation ships without test coverage; the org-wide floor (75%) is the gate.
8. **Named to convention** (§6) and versioned cleanly (no orphan inactive versions).

## 2. The layered model — what goes where

| Layer | Runs | Use for | Don't use for |
|---|---|---|---|
| **Before-save flow** | Same transaction, no DML cost | Field defaulting, cross-field validation, same-record stamping | Anything touching other objects |
| **Trigger handler (Apex)** | Before/after | Bulk cross-object logic, recursion control, complex queries, anything needing tests/governor control | Simple field updates a flow can do |
| **After-save flow** | After commit of this record | Cross-object updates, notifications, subflow orchestration | Heavy bulk loops (push to Apex) |

Rule of thumb: **declarative for the simple and changeable; Apex for the bulk and complex.** One of each per object, not many.

## 3. Trigger framework (Apex reference)

- A single virtual `TriggerHandler` base class (context dispatch, recursion guard, CMDT bypass).
- One `<Object>TriggerHandler` per object extends it; overrides only the contexts it needs.
- One trigger per object: `trigger OpportunityTrigger on Opportunity (before insert, ...) { new OpportunityTriggerHandler().run(); }`
- Bypass via CMDT (`Trigger_Setting__mdt`) and a static set, so any handler can be disabled per-env or in a data-load without a deploy.
- Reference implementation: `TriggerHandler.cls`, `OppTriggerHandlerReference.cls` (named *Reference to avoid colliding with the org's existing `OpportunityTriggerHandler`), `TriggerHandler_Test.cls`, plus `TestDataFactory.cls` (reusable test-data builders). NOTE: the org already has an `OpportunityTriggerHandler` — Phase C consolidates INTO it / replaces it under change control, it is not overwritten ad hoc.

## 4. Flow orchestrator pattern

- `Opportunity_BeforeSave_Orchestrator` (RecordBeforeSave, Create+Update): entry checks the `Application_Settings__c` bypass; calls before-save concern subflows in a defined order; each call has a fault path → `Platform_Fault_Logger`.
- `Opportunity_AfterSave_Orchestrator` (RecordAfterSave): same shape for after-save concerns.
- Concerns become **subflows** (`OppSF_<concern>`), independently testable and reusable, never standalone record-triggered flows.

## 5. Configuration & observability (already partly built)

- **Bypass:** extend the existing `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c`; add per-automation switches in CMDT.
- **Fault logging:** `Platform_Fault_Logger` (built) on every fault path → `Flow_Log__c`.
- **Monitoring:** the REV-71 Flow_Log list view/report pattern; add a per-object dashboard tile.
- **Alerting:** `Fault_Alert_Setting__mdt` (built), opt-in.

## 6. Naming conventions

- Triggers: `<Object>Trigger` (one only). Handlers: `<Object>TriggerHandler`.
- Orchestrators: `<Object>_BeforeSave_Orchestrator` / `<Object>_AfterSave_Orchestrator`.
- Concern subflows: `<ObjAbbr>SF_<Concern>` (e.g. `OppSF_StampCloseDate`).
- CMDT: `<Area>_Setting__mdt`. Tests: `<Class>_Test`.

## 7. Migration process (per object, safe sequence)

1. **Cover first** — bring the object's existing custom Apex to ≥75% so regressions are caught.
2. **Inventory & classify** — the decommission map (§9 for Opportunity).
3. **Build the orchestrators + handler** behind bypass switches (inert).
4. **Port concerns** one at a time into subflows/handler methods, with tests, comparing behaviour in a sandbox against the legacy flow.
5. **Cut over** — activate the orchestrators, deactivate the legacy flows/triggers (don't delete yet).
6. **Soak** — monitor Flow_Log for a release; then delete the legacy components.
7. Repeat for the next object.

---

## 8. Why this is the scalable answer (vs. patching)

Wiring fault paths into 266 flows is O(flows × elements) of toil and leaves the structure intact.
Consolidation is O(objects): ~30 standardised pipelines for the whole core estate, each
observable and tested. You maintain a pattern, not a sprawl. **Opportunity 22 automations → 1
trigger handler + 2 orchestrators (+ untouched managed packages).**

## 9. Opportunity decommission map (the worked example)

### Triggers (9) — only the 3 custom ones consolidate; managed packages stay

| Trigger | Owner | Disposition |
|---|---|---|
| `OpportunityTrigger` | custom | **Merge** → OpportunityTriggerHandler |
| `Ast_OpportunityTrigger` | custom | **Merge** → handler |
| `OpportunityTriggerMBLChangeEvent` | custom | **Merge** → handler (or keep if CDC-specific) |
| `RHX_Opportunity` | Rollup Helper (pkg-generated) | **Leave** — package-owned |
| `OpsosOpportunityTrigger` (DOZISF) | ZoomInfo | **Leave** — managed |
| `OpportunityBefore` (sbaa) | Advanced Approvals | **Leave** — managed |
| `OpportunityBefore` / `OpportunityAfter` (SBQQ) | CPQ | **Leave** — managed |
| `OpportunityTR` (trumpet) | trumpet | **Leave** — managed |

→ **3 custom triggers collapse to 1 handler; 5 managed triggers untouched.** The "9 triggers" problem is really a "3 triggers" problem.

### Flows (12) — collapse to 2 orchestrators + keep before-delete

| Flow | Timing | Disposition |
|---|---|---|
| Opportunity_BeforeSaveFlow | before-save | → `Opportunity_BeforeSave_Orchestrator` (subflow) |
| Update_Opportunity_Contract_Attached_Field | before-save | → before-save subflow |
| UltimateAccountBeforeSaving | before-save | → before-save subflow |
| Complete_Customer_Success_Task_validation | before-save | → before-save subflow (validation) |
| Check_Completeness_of_Contact_Roles | before-save | → before-save subflow (already CMDT-driven from prior work) |
| Opportunity (generic) | after-save | → `Opportunity_AfterSave_Orchestrator` (subflow) |
| Customer_Journey | after-save | → after-save subflow — **rebuild during port** (hardcoded IDs, 154K chars) |
| Direct_Debit_and_Credit_Card_Notification... | after-save | → after-save subflow (notification) |
| Opportunity_Email_alert_for_LexPro_closed_won_opps | after-save | → after-save subflow (notification) |
| Opp_Error_Saleshandshake | after-save | → after-save subflow |
| Check_Contact_Role_Log_Faults | after-save | → fold into the shared fault framework |
| Opportunity_Prevent_user_from_deleting_opportunities | before-delete | **Keep** (or fold into handler before-delete) |

→ **11 create/update flows collapse to 2 orchestrators**; the before-delete stays. Each concern becomes a tested subflow/handler method, fault-guarded.

**Net for Opportunity:** from 9 triggers + 12 flows + 1 WF across 3 paradigms (unknowable order) to
**1 trigger → 1 handler + 2 orchestrator flows** (deterministic, observable, tested), with managed
packages untouched. That is the unit other objects are rebuilt to.
