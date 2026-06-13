# Centellic — Debt-Reduction Programme to a World-Class Standard
### Grounded execution plan · companion to the diagnostic + automation standard · 13 Jun 2026

This is the sequenced programme that takes the org from its current debt to the world-class
target architecture. It is grounded in the org's **real numbers**, not generic advice, and it
sequences the work by dependency — because doing it in the wrong order is unsafe.

---

## 1. The single most important finding: the debt is BOUNDED

| Metric | Reality (measured) | Implication |
|---|---|---|
| Custom Apex | **~4,100 lines across 74 classes/triggers** | The custom estate is *modest* — the 6,445-class headline is ~98% managed packages |
| Test coverage | **2.1% (86/4,100 lines); 68 of 74 units at 0%** | The gate to safe change — but only ~3,000 lines to cover, **weeks not years** |
| Custom triggers to consolidate | **~3–4 per core object** (rest are managed) | The "9 triggers on Opportunity" is really a 3-trigger job |
| Live flow failures | **~120 in 4 days** (not 1,218 — 90% was historical residue) | The real reliability problem is small and targetable |

**The headline debt is real but tractable.** This is a months-long programme, not a multi-year rescue.

## 2. Why the order matters (the dependency that governs everything)

> **You cannot safely consolidate automation at 2% test coverage.** With no regression net, every
> change to the Opportunity/Quote/Lead pipelines is a blind risk, and clean deploys are blocked by
> the 75% floor. **Test coverage is the foundation gate. It comes before consolidation, not after.**

This is why the programme is sequenced as below and not "fix the flows first."

## 3. The programme (sequenced by dependency)

### ✅ Phase A — Stabilise & instrument (largely DONE)
Make failures visible and stop new silent ones. *Delivered:*
- `Platform_Fault_Logger` shared fault framework (deployed) + `Fault_Alert_Setting__mdt`.
- Flow_Log monitoring (REV-71 list view/report pattern).
- Pilot fault path on the #1 live-error flow (Opportunity Contact Role).
- Read-only diagnostic + findings register + automation standard + trigger framework.
*Remaining:* purge the 1,098 stale errored interviews (housekeeping); roll the fault framework to prod.

### 🔴 Phase B — Coverage foundation (THE GATE — do next)
Bring custom Apex to ≥75% and add CI enforcement, so consolidation becomes safe.
**Grounded, risk-ranked target list (largest 0%-covered first):**

| Priority | Class | Uncovered lines | Why first |
|---|---|---|---|
| 1 | `RenewalOpportunityHandler2` | 479 | Largest; renewal-critical (revenue path) |
| 2 | `OpportunityAnalyticsCreate` | 164 | On a consolidation-target object; recently changed |
| 3 | `Ast_RenewalEmailSender` / `Ast_RenewalEmailHelper` | 218 / 163 | Renewal comms |
| 4 | `CreateEventBundleUsingCSV` / `CloneEventProduct` | 437 / 209 | Events; bulk/data-load risk |
| 5 | `ESignGlobalApiCallout` / `ESignGlobalAgrViewCtrl` | 202 / 289 | External callouts — fragile, untested |
| 6 | `LBRInteractionReparentService`, `ALMSplitLineItemBatch*`, … | 79–88 | Smaller, finish the tail |

Approach: one class at a time, behaviour-pinning tests (assert current behaviour first, so you can
refactor safely later). Add a CI gate (`RunSpecifiedTests` per change, org-wide ≥75% before consolidation).
**Effort: ~3–5 focused weeks** for ~3,000 lines. This is the highest-ROI debt work in the org.

### 🟠 Phase C — Consolidate per object (the rebuild — needs B first)
Using the **Automation Standard** + **TriggerHandler framework** (both delivered), object by object,
worst first: **Opportunity → Quote → Lead → Contact → Account**. Per object, follow the §7 migration
process: cover → classify (decommission map) → build orchestrators+handler behind bypass → port concerns
with parity tests → cut over → soak → delete legacy. Opportunity decommission map already done.

### 🟡 Phase D — Modernise & de-bloat
Migrate the 8 Workflow Rules + 6 Process Builder processes into the model; API-version uplift on the
stale Apex tail; Dynamic Forms on the 94/80-field layouts; retire redundant validation rules (Opp's 29).

### 🟢 Phase E — Optimise & govern
Journey-level click reduction; reusable subflow/action library; governance model (Modify-All review,
record-type rationalisation, naming/version hygiene, change control); per-object reliability dashboards.

## 4. How the delivered assets slot in

| Asset (built) | Serves |
|---|---|
| `Platform_Fault_Logger` + `Fault_Alert_Setting__mdt` | Phase A/C — observability on every pipeline |
| Flow_Log monitoring view/report | Phase A/E — measurable reliability |
| `TriggerHandler` framework (77% cov, tested) | Phase C — the Apex consolidation engine |
| Automation Standard + Opportunity decommission map | Phase C — the repeatable blueprint |
| This programme + grounded coverage list | Phase B/C — the execution plan |

## 5. Definition of "world-class" (the bar we're holding)

An object is "done" when: **one** trigger→handler + **one** before/after orchestrator flow; **zero** WF/PB;
all environment refs in CMDT; **every** fault path logs; **≥75%** tested with behaviour-parity; legacy
components deleted; and reliability is visible on a dashboard. The org is world-class when every core
object meets that bar and a CI gate prevents regression.

## 6. What I recommend right now
Start **Phase B** — it's the gate, it's bounded (~3,000 lines), and it unlocks everything. Begin with
`RenewalOpportunityHandler2` (largest, revenue-critical). I can write behaviour-pinning tests class by
class in KJDEV, each deployed and green, raising org coverage measurably toward the 75% floor.
