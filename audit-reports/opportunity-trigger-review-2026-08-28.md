# OpportunityTrigger review — full recommendation

**Date:** 28 Aug 2026 · **Reviewer:** CRM engineering (Kamyar's team) · **Trigger version:** PROD as retrieved 28 Aug
**Context:** the FINEST-trace league table (27 Aug) attributes **32 SOQL queries** of the failing
rep-save transaction to `OpportunityTrigger` — the largest single code contributor. Three SOQL-101
incidents in two days all died at the Opportunity master flow chain's own commit; the chain plus this
trigger saturate the transaction on routine renewal saves. This review explains where the 32 come
from and exactly how to reclaim most of them.

---

## 1. What the trigger runs

`OpportunityTrigger` (after insert, after update, before insert, before update) dispatches to five units:

| Unit | Timing | Purpose |
|---|---|---|
| `OpportunityTriggerHandler.handleAfterInsertUpdate` → `ProcessLineItems.updateDealYears` | after update | Recomputes Deal Start/End Year on line items from product editions |
| `OpportunityAnalyticsCreate.createRecords` | after update | Snapshot records for the analytics feature |
| `OpportunityHandler.LockOppRecords` | after insert + update | Locks/unlocks records around closed stages; submits SBAA approvals |
| `OpportunityChangePublisher.publishFor` | after insert + update | Publishes `Opportunity_Change__e` events for MBL-linked accounts |
| `OpportunityBillingEntityHandler.evaluate` | before insert + update | Derives `Billing_Entity__c` from type / previous opp / line locations |

`Ast_OpportunityTrigger` is already an empty merged stub (good). `RHX_*` triggers are rh2's, out of scope here.

## 2. Where the 32 queries come from

The killer is not any single query — it is **per-save cost × repeated saves**. CPQ and the flow chain
save the same opportunity 3–4 times inside one transaction, and none of these handlers memoize, so
everything below runs **every save**:

| # | Source | Queries per save | Defect class |
|---|---|---|---|
| 1 | `OpportunityHandler.LockOppRecords` — `Approval.isLocked(opp.id)` called **inside the per-record loop**, for closed-stage opps *and* in the else-branch for every non-closed opp | 1 × N records | **Query in loop** — the textbook one. On a 200-record renewal batch this alone is 200 queries |
| 2 | `ProcessLineItems.updateDealYears` — comment says "async" but the method is **synchronous**: OLI query + OLI DML on every after-update, cascading into the whole OLI trigger stack (rh2 rollups included) | 1 + DML cascade | Mislabelled sync work; fires with **no change detection** on the fields it derives from |
| 3 | `OpportunityAnalyticsCreate.createRecords` — **now live**: both `Opportunity_Analytics_Settings__mdt` records read `IsActive__c = true` (it was deployed dormant; the non-deterministic `LIMIT 1` no longer protects because both rows are true) | ~4 | Feature activated silently; duplicate switch records were never cleaned |
| 4 | `OpportunityBillingEntityHandler.evaluate` — has decent change-gating (good!), but: the `Opportunity_Billing_Entity_Mapping__c` **custom setting is read via SOQL** (counts) instead of the free `getAll()` cache; the OLI + previous-opp queries re-run each save because `blankWithLineItems` keeps `shouldRun` true for any open opp with lines and no billing entity | 1–3 | Custom-setting SOQL; gate leaks on the blank-entity path |
| 5 | `OpportunityChangePublisher.publishFor` — Account query + full Opportunity **re-query of Trigger.new records** (fields it could mostly read from Trigger.new + one Owner lookup); runs even when nothing relevant changed; CMDT gate itself is exempt (fine) | 2 | Redundant re-query; no change gating |

**Arithmetic:** ~9–10 countable queries per save × 3–4 saves per transaction ≈ **30–36** — matching the
measured 32. The multiplier (repeated saves) doubles the value of every fix below.

## 3. Recommendation

### Phase 1 — the two whales (do first; ~1 day; zero behaviour change)

**1a. Bulk + memoize the lock check.** Replace per-record `Approval.isLocked(opp.id)` with one
`Approval.isLocked(List<Id>)` call per invocation, **and** skip the check entirely unless the record's
stage actually crossed the closed/open boundary this save (compare old vs new stage before touching
the API). A static per-transaction set of already-processed ids makes repeat saves free.
*Effect: N queries → 0 on most saves, 1 when a stage genuinely transitions.*

**1b. Make deal-years honest about being async — and gated.** Give `updateDealYears` the `@future`
(or Queueable) it always claimed to have, and only enqueue when a field it derives from changed
(product lines / close date — confirm the derivation inputs with the owner). A static per-transaction
guard prevents duplicate enqueues across repeated saves.
*Effect: 1 query + an OLI DML cascade off the synchronous path on every save.*

### Phase 2 — the quiet leaks (half a day)

**2a. Analytics switch hygiene.** Decide deliberately whether `OpportunityAnalyticsCreate` should be
live. Either way: delete the duplicate CMDT record and make `isFeatureActive()` filter on
`DeveloperName` instead of a bare `LIMIT 1`. If it stays live, add a static per-transaction
first-save-only guard. *Effect if returned to dormant: −4 per save.*

**2b. Billing entity handler.** Swap the custom-setting SOQL for `Opportunity_Billing_Entity_Mapping__c.getAll()`
(cached, free); add a static per-transaction memo so the OLI/previous-opp queries run once per
transaction, not per save — the `blankWithLineItems` re-entry is the leak.
*Effect: 3 → ~1 per transaction.*

**2c. Change publisher.** Gate on relevant change (stage/amount/owner — the event's own payload
fields) before querying anything; drop the Opportunity re-query by reading Trigger.new plus one
cached Owner lookup; memoize the Account map per transaction.
*Effect: 2 per save → ~1 per transaction, and far fewer platform events.*

### Phase 3 — structure (with the master-flow refactor)

Adopt one **trigger-handler frame with per-transaction state** (a static context object carrying
processed-id sets and cached maps) so every current and future unit is repeat-save-safe by default.
This is the same discipline that fixed REV-60 (transaction idempotency cache) and should be the house
pattern. Sequence it with Saurabh's master-chain refactor — the two together are the structural end
of the 101s; everything else is margin management.

### Expected outcome

| State | Trigger cost in the failing transaction |
|---|---|
| Today | ~32 |
| After Phase 1 | ~12–14 |
| After Phase 2 | **~3–5** |

Combined with the ~20 already removed (rh2 async, REV-60 cache + async, Order Form diet — now 2 per
quote save), the transaction lands comfortably clear of the limit even before the master chain is
restructured.

## 4. Risks & testing

- **Lock semantics:** bulk `Approval.isLocked` is behaviour-identical; the stage-transition gate must
  keep one edge — records *created* directly in a closed stage (the existing insert branch covers it).
  Test matrix: open→closed, closed→open, closed→closed edit, closed insert, bulk 200.
- **Deal years async:** verify no consumer reads Deal_*_Year within the same transaction (reports and
  rollups are fine with seconds of latency; check any same-save formula/flow dependency first).
- **Analytics:** confirm with the feature owner before flipping the switch back; the silent activation
  itself is a finding worth a process note (CMDT records are data — they move with sandbox refreshes
  and manual edits, invisible to deployment review).
- All changes are additive/gating — each phase ships independently and reverts independently.

## 5. Ownership

The trigger units span at least three authors (in-house, astreait, analytics). Recommend Saurabh owns
Phase 1–2 execution with this document as the spec; CRM (Kamyar) validates via the FINEST-trace
league table before/after — the same measurement that produced the 32.
