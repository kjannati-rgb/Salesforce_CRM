# Centellic (Law Business Research) — Salesforce Platform Diagnostic
### Read-only discovery · Production org `00D6g0000081IOgEAM` (GBR46, Unlimited Edition) · 13 Jun 2026

**Scope:** read-only diagnostic of the two presenting problems — (1) automation fails too often,
(2) processes take too many clicks. No metadata or data was written. Every finding cites evidence
(component, query result, or parsed XML). Structural reliability findings come from parsing flow
XML retrieved from production; inventory/error signals from the Tooling API.

---

## 1. Executive summary

**Health scorecard (RAG):**

| Dimension | Rating | One-line basis |
|---|---|---|
| **Reliability** | 🔴 **Critical** | 10% flow fault-path coverage; 1,218 flow interviews in Error; 2% Apex test coverage |
| **Maintainability** | 🔴 **Critical** | Opportunity = 22 automations across 3 paradigms; Lead/Contact/Account 11–17 each |
| **UX / clicks** | 🟠 **High** | 94-field Opportunity layout, 80-field Lead; 29 validation rules on Opportunity |
| **Governance** | 🟡 **Medium** | Healthy permission-set adoption, but 33 users with Modify All Data, API v38→v66, no test safety net |

**Root-cause themes:**
1. **No error-handling discipline in declarative automation.** 90% of DML/lookup/action elements in
   the busiest flows have no fault path — failures surface raw to users instead of being caught/logged.
2. **Severe automation pile-up on core objects.** Multiple paradigms (Workflow Rules + Process Builder
   + Flows + many Apex triggers) coexist on Opportunity, Lead, Contact, Account — unpredictable
   order-of-execution and re-entrancy.
3. **Hardcoded IDs from the ALM merger.** Queue/RecordType/User IDs are embedded literally in flows;
   they break on config/data drift (exactly the `Customer_Journey` picklist-class failure).
4. **No automated test safety net.** 2% org-wide coverage means no regression protection and a hard
   block on clean deployments.
5. **Layout & validation bloat** drives the click problem on the core revenue journey.

---

## 2. Findings register

Severity: Critical / High / Medium / Low · Effort: S/M/L · Impact: H/M/L

| ID | Area | Sev | Finding & evidence | Root cause | Recommendation | Eff | Imp |
|---|---|---|---|---|---|---|---|
| R-01 | Reliability | **Critical** | **10% fault-path coverage** across 51 active record-triggered flows on hot objects — 229 of 255 DML/lookup/action elements have no `<faultConnector>` (parsed flow XML). | No error-handling standard | Add fault paths routing to a shared error-logger subflow; start with top-traffic flows | M | H |
| R-02 | Reliability | **Critical** | **`Customer_Journey` flow: 59 unguarded elements (0% coverage) + 12 hardcoded IDs** (5 Queue, 7 RecordType — spanning 3 ID instances `0124L…/0126g…/012Tm…`). The cited live failure exemplar. | Merger migration + no fault handling | Rebuild with CMDT-driven IDs + fault paths (sandbox repro first) | L | H |
| R-03 | Reliability | **Critical** | **1,218 Flow interviews in `Error` status** (`SELECT InterviewStatus, COUNT(Id) FROM FlowInterview`). | Cumulative unhandled flow failures | Triage by flow; fix top offenders; add alerting | M | H |
| R-04 | Reliability | **Critical** | **Org-wide Apex test coverage = 2%** (`ApexOrgWideCoverage`). Deploy floor is 75%. | No test discipline | Backfill tests on the 134 custom classes; gate via CI | L | H |
| R-05 | Maintainability | **Critical** | **Opportunity carries 22 automations across 3 paradigms:** 9 Apex triggers + 12 record-triggered flows + 1 Workflow Rule. Lead 12+4+1, Contact 11+4+1, Account 11+3 (Tooling inventory). | Organic accretion + merger | Consolidate to 1 trigger handler + 1 before/1 after flow per object, orchestrated | L | H |
| R-06 | Maintainability | **High** | **Multiple custom triggers per object** — e.g. Opportunity has `OpportunityTrigger`, `Ast_OpportunityTrigger`, `OpportunityTriggerMBLChangeEvent` + managed. Violates one-trigger-per-object. | No trigger framework | Single dispatcher per object | M | H |
| R-07 | Reliability | **High** | **Hardcoded User ID in `Contract_Create_1`** (`0056g000005shq8AAA`) + RecordType ID. Breaks if that user is deactivated. | Convenience hardcoding | Replace with CMDT / running-user / queue-by-name | S | M |
| R-08 | Reliability | **High** | **CPQ async failures** — `QueueableCalculatorService` 16 failures / 7 days, `QueueableQuoteDocumentService` 8 (`AsyncApexJob`). | CPQ calc-service fragility | Investigate calc-service auth/timeouts; add retry/alert | M | M |
| T-01 | Tech debt | **High** | **8 Workflow Rules + 6 active Process Builder processes** still live (both retired by Salesforce). | Un-migrated legacy | Migrate to record-triggered flows | M | M |
| U-01 | UX/clicks | **High** | **Opportunity main layout = 94 field placements** (8 required), **Lead = 80** (parsed layout XML). Well past the ~50 bloat threshold. | Layout accretion | Dynamic Forms + field rationalisation on core journeys | M | H |
| U-02 | UX/clicks | **High** | **294 active validation rules; 29 on Opportunity, 22 on Quote, 13 on QuoteLine** (Tooling). Heavy save-time friction + conflict risk. | Rule accretion | Audit/retire redundant VRs; consolidate logic | M | M |
| U-03 | UX/clicks | **Medium** | **Opportunity has 15 layouts / 4 record types; Campaign 10 record types** (Tooling). Layout/branch sprawl. | Profile-based layout proliferation | Rationalise record types & layout assignments | M | M |
| G-01 | Governance | **Medium** | **33 user assignments carry Modify All Data** (`PermissionSetAssignment`). Over-broad. | Permission convenience | Review; restrict to admins; use scoped perms | S | M |
| G-02 | Governance | **Medium** | **API version spread v38→v66** across 134 custom Apex classes (stale tail: v38, v45, v50, v53). | No uplift cadence | Periodic API-version uplift with test cover | M | L |
| G-03 | Housekeeping | **Low** | **117 inactive/draft flow definitions** of 383 total (Tooling). Clutter, version confusion. | No retirement process | Archive/delete obsolete flow versions | S | L |
| G-04 | Governance | **Low** | ~6,300 managed-package Apex classes (6,445 total − 134 custom) — heavy post-merger package footprint. | Merger + tool accretion | Package rationalisation review (licences/usage) | L | L |

*Positive note:* the org already leans modern on permissions — **461 permission sets / 24 permission-set
groups vs 40 profiles** — and unmanaged triggers correctly delegate to handler classes (no SOQL/DML in
trigger bodies). The foundations for consolidation exist.

---

## 3. Remediation roadmap (impact × effort)

### 🔴 Stabilise (0–4 weeks) — stop the bleeding
- **Stand up a shared error-logging/alerting framework** (reuse the existing `Flow_Log__c` + a generic
  fault subflow) and wire the top-traffic flows' DML to it. *(R-01, R-03)* — **quick win: high impact**
- **Rebuild `Customer_Journey`** with CMDT-driven IDs and fault paths (sandbox repro → deploy). *(R-02)*
- **Strip hardcoded IDs** from `Customer_Journey`, `Opportunity`, `Contract_Create_1` (User ID is the
  most urgent time-bomb). *(R-02, R-07)* — **quick win**
- **Triage the 1,218 errored interviews** — group by flow, fix the top 3–5 sources. *(R-03)*

### 🟠 Consolidate (1–3 months) — collapse the pile-up
- **One trigger handler per object** on Opportunity/Lead/Contact/Account via a dispatcher framework. *(R-05, R-06)*
- **One before-save + one after-save flow per object**, with documented orchestration; merge the 12
  Opportunity flows / 9 Quote flows. *(R-05)*
- **Validation-rule audit** — retire redundant rules (start with Opportunity's 29). *(U-02)*
- **Backfill Apex tests** toward the 75% floor on the 134 custom classes; add CI gating. *(R-04)*

### 🟡 Modernise (3–6 months)
- **Migrate the 8 Workflow Rules + 6 Process Builder processes to flows.** *(T-01)*
- **API-version uplift** on the stale Apex tail. *(G-02)*
- **Dynamic Forms rollout** on Opportunity/Lead/Account to cut the 94/80-field layouts. *(U-01)*

### 🟢 Optimise (6 months+)
- **Journey-level click reduction** across Lead → Opp → Quote → renewal; default deterministic fields. *(U-01, U-03)*
- **Reusable subflow / invocable-action library** to stop re-implementation.
- **Governance model:** Modify-All review, record-type rationalisation, flow naming/version hygiene,
  change-control. *(G-01, U-03, G-03)*

**Explicit quick wins:** error-framework + hardcoded-ID strip + `Customer_Journey` rebuild deliver the
biggest reliability gain for least effort and should go first.

---

## 4. Recommended target architecture

Converge on **one record-triggered flow per object per timing** (one before-save for field defaulting/validation,
one after-save for cross-object work) plus **one Apex trigger per object delegating to a single handler class**,
with a documented, deterministic order between the flow and Apex layers. All environment-specific references
(IDs, queues, record types) move to **Custom Metadata**, never hardcoded. Every DML/callout element routes its
fault path to a **shared error-logging + alerting subflow**. Legacy Workflow Rules and Process Builder are
retired into this model. This collapses the current 3-paradigm, 22-automation Opportunity stack into a single
predictable, observable, testable pipeline — directly fixing both presenting problems (reliability via fault
handling + determinism; clicks via consolidated validation and Dynamic Forms).

---

## 4a. Errored-interview drill-down (read-only) — LIVE vs HISTORICAL

**Important correction (verified 13 Jun):** of 1,218 errored interviews, **1,098 (90%) are historical
residue, not live failures.** The top source — "Opportunity Analytics: Update record" (775) — comes from
two flows (`Opportunity_analytics_product_edited`, `opportunity_analytics_OA_update`) that are **now
INACTIVE**, replaced by the active Apex class `OpportunityAnalyticsCreate` (v62). Those errors **stop on
9 Jun** (the deactivation point); they are stale records that can be purged as housekeeping, not remediated.

**LIVE error profile — last 4 days (≈120 interviews), the real reliability targets:**

| Live errors (4d) | Flow | Fails at | Note |
|---|---|---|---|
| **64** | **Opportunity Contact Role: Check for Duplicate** | `Get_Contact_Role` | **#1 live offender** — lookup faulting on every duplicate-check |
| ~24 | **Opportunity_AfterUpdate_MasterFlow** | (multiple) | Failing across many sales users (saurabh.patil, william.anderson, sarika.sandhu, willie.guerrero…) — broad daily impact |
| 10 | Order Process Builder Migrate | `Update_Records_as_Activated` | Legacy PB-migrated flow (T-01) |
| 8 | Opportunity: Currency update screen flow | `Update_opportunity_currency2` | — |
| 6 | **Customer Journey** | `Get_Group_..._Ids` | **Confirms R-02 — hardcoded queue lookups erroring** |

**Pilot + root-cause notes (KJDEV repro, 13 Jun):**
- **Opportunity Contact Role: Check for Duplicate (64 live)** — repro confirmed the Custom Error
  duplicate-block fires correctly AND does **not** persist a FlowInterview, so the 64 errored interviews
  are **genuine faults at `Get_Contact_Role`**, not the dup-block. Trivial lookup → almost certainly
  **governor-limit exhaustion** from the Opportunity 22-automation transaction pile-up. **Fixed (interim):**
  fault path added → `Platform_Fault_Logger` (logs + save proceeds, no raw error); the log will capture the
  exact message in prod to confirm the governor hypothesis and target the deeper fix (transaction consolidation).
- **Customer Journey (6 live, fails at `Get_Group_*`)** — root cause is mixed: some queues looked up
  dynamically by Name ('Case - Lex PRO') that can return empty post-rename, plus **5 hardcoded queue IDs +
  7 hardcoded RecordType IDs** scattered across a 154K-char flow (20 lookups / 21 decisions). **This is a
  scoped rebuild, not an inline edit** — fix approach: replace every hardcoded queue/RT ID with a dynamic
  lookup by DeveloperName (or CMDT), guard each lookup with the shared fault logger, in a dedicated change
  with full repro. Overlaps the existing Customer Journey workstream.

**Revised R-03 priority:** the live remediation targets are **Opportunity Contact Role: Check for Duplicate**
and **Opportunity_AfterUpdate_MasterFlow**, not the retired Analytics flow. Two lessons stand on their own:
(a) deactivated-but-not-deleted flows leave a large stale-error backlog that masks the live signal —
a monitoring/housekeeping gap; (b) the Apex replacement was done correctly (flow off, Apex on) — evidence
the team *can* execute the consolidation pattern this roadmap recommends. Caveat: errored interviews persist
only for roll-back-on-error flows; fault-and-continue flows don't persist, so true live rate is somewhat higher.

## 5. Assumptions & access gaps
- **"Centellic" = Law Business Research production** (`kamyar.jannati@lbresearch.com`, IsSandbox=False) — the
  only production org on the connection; confirmed via `Organization` query.
- **Flow structural analysis** covered the **51 active record-triggered flows on the 10 hottest objects** (the
  highest-risk set), not all 266 active flows — coverage figures are representative of those, not org-wide.
- **Apex deep-dive** was limited to trigger bodies + metadata (134 custom classes); handler-class internals
  (bulkification, governor headroom per transaction) were not line-by-line reviewed — a sandbox profiling pass
  is the right follow-up.
- **Errored-interview root causes** are counted, not individually opened (error detail isn't fully retained
  without Event Monitoring, which licensing wasn't confirmed).
- No data or metadata was modified at any point.
