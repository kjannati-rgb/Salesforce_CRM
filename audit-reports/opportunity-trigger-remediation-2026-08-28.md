# OpportunityTrigger remediation — Phases 1 & 2 executed

**Date:** 28 Aug 2026 · **Executed by:** CRM engineering (Claude, for Kamyar) · **Spec:** `opportunity-trigger-review-2026-08-28.md`
**Deployed:** KJDEV → FULLUAT → LBR_PROD, all green, 28 Aug 2026 (PROD deploy id `0AfPx000001JvObKAK`, 24/24 specified tests)

## Result — the deliverable numbers

Measured with the 27 Aug league-table method: `Database=FINEST`-class trace on a real PROD
opportunity save (no-op REST PATCH of `006Px00000Rz6VZIAZ`, "Test" on Kelsey's Test Company,
14 line items), counting `SOQL_EXECUTE_BEGIN` inside `OpportunityTrigger` `CODE_UNIT` blocks.
One user save runs the trigger through **two full cycles** in this transaction (flow-chain
re-save), so per-save numbers are half of these.

| State | SOQL attributed to OpportunityTrigger (2 cycles) | Per save cycle |
|---|---|---|
| Before (28 Aug, pre-deploy) | **18** | 9 |
| After (28 Aug, post-deploy) | **8** | 4 |
| After, if the analytics switch is turned off | **0** | 0 |

Whole transaction: 23 → 13 total SOQL. Scaled to the failing CPQ transaction (3–4 saves),
the trigger's contribution drops from the measured ~32 to ~12–16 — and to **~0** once the
analytics on/off decision (below) is made, beating the review's ~3–5 target.

**All 8 remaining queries are `OpportunityAnalyticsCreate`'s 4 queries × 2 cycles.** Every
other source was eliminated:

| Defect (review §2) | Fix | Queries now |
|---|---|---|
| 1. `OpportunityHandler.LockOppRecords` per-record `Approval.isLocked` | One bulk `Approval.isLocked(List<Id>)`; runs only when StageName crosses the closed/open boundary; static per-transaction processed-id set; closed-stage inserts lock without any check (new records are never locked) | 0 on normal saves; 1 bulk call on a genuine transition |
| 2. `ProcessLineItems.updateDealYears` synchronous "async" | Now a real Queueable, enqueued only when the line set changed (`No_of_Line_Items__c` roll-up or `Amount` moved — line edits system-fire the trigger with those changed) + `HasOpportunityLineItem` gate + per-transaction dedupe; sync fallback when the queueable budget is exhausted | 0 sync; 1 async job per transaction with line changes |
| 3. `OpportunityAnalyticsCreate` bare `LIMIT 1` | `isFeatureActive()` now reads `Opportunity_Analytics_Settings__mdt.getInstance('Switch')` (deterministic, cached, zero SOQL); duplicate `Default` record deactivated (`IsActive__c=false`) in all three orgs | 4 per save **while the feature is on** (see decision) |
| 4. `OpportunityBillingEntityHandler` custom-setting SOQL + `blankWithLineItems` re-query | `Opportunity_Billing_Entity_Mapping__c.getAll()` (cached, zero SOQL); static per-transaction memo for OLI-countries and previous-opp lookups, evicted for an opp when its line count changes | 0–2 once per transaction, 0 on repeat saves |
| 5. `OpportunityChangePublisher` re-query + no gating | Gates on payload-field change (Stage/Amount/Owner/Account) before anything; reads Trigger.new directly (no Opportunity re-query); cached Owner lookup; per-transaction Account memo. Also far fewer platform events | 0 on irrelevant saves; ≤2 once per transaction |

## ⚑ DECISION NEEDED — Kamyar

`Opportunity_Analytics_Settings__mdt` had **both** records (`Default`, `Switch`) at
`IsActive__c=true` in PROD — the feature that was deployed dormant is **live**, activated
silently at some point (CMDT records are data; they move with refreshes and manual edits).
This work made the read deterministic (`Switch`) and deactivated the duplicate, which
**preserves the current live state** — no behaviour change was made.

- **Leave live:** costs 4 queries per save cycle (8–16 per transaction) — the only remaining
  trigger cost. A per-transaction first-save-only guard could cut it to 4 per transaction but
  risks snapshotting before CPQ finishes its mid-transaction line changes — needs the feature
  owner's view on snapshot timing.
- **Return to dormant:** flip `Switch` to `IsActive__c=false` (one CMDT record deploy or
  Setup edit). Trigger cost on a routine save drops to ~0.

## Behaviour notes (reviewed, intentional)

- **Closed→closed stage edits no longer re-lock.** Previously an unlocked record edited
  within the closed set was re-locked on save; the boundary gate skips that. SBAA
  submit-for-approval behaviour is byte-for-byte unchanged (still fires on any stage change
  into a submit stage, including closed→closed like `Closed Lost` → `Cancellation - Pending
  Review`). Records inserted directly in a closed stage still lock and submit.
- **Deal-years recalc is now async** (seconds of latency). Verified via the Dependency API
  that `OpportunityLineItem.Deal_Start/End_Year__c` are consumed only by batch Apex
  (`ALMSplitLineItemBatch(Lost)`, `ProcessLineItemsBatch`) — no flow, formula, VR, or
  same-transaction reader exists. A recalc failure now surfaces as a failed queueable job
  rather than a save error (pre-existing null-unsafe `Clean_Product_Code__c.left(9)` left
  as-is).
- **Publisher with a missing `MBL_Custom_Event` CMDT record** now treats it as "off" instead
  of throwing an uncatchable QueryException on every save (this was live-crashing in KJDEV,
  which lacked the record — see parity fixes).
- **Deal-years recalc no longer runs on saves with no line-set change** (e.g. stage-only
  edits). Staleness from direct `Product2` field edits is no longer self-healed by unrelated
  opp saves — the existing batch classes remain the sweep for that.

## Org parity fixes made along the way

- **KJDEV:** deployed `Ast_Trigger_Setting.MBL_Custom_Event` CMDT record (existed in
  PROD/FULLUAT only; its absence made every opp-with-account save throw in KJDEV).
- **FULLUAT:** `Reporting_Stream` global value set was 24 values behind PROD (strict subset —
  nothing dropped) and `Product2.Reporting_Stream__c` dependency matrix was stale; synced
  both from PROD. This was breaking `OpportunityAnalyticsCreate_Test` in FULLUAT
  (`Events - LIL` rejected).

## Test coverage added

`OpportunityHandlerTest`: full review matrix — open→closed locks, closed→open unlocks,
closed→closed edit consumes zero queries, closed insert locks via real trigger, bulk 200 =
one bulk isLocked query + free repeat save. `TestOpportunityTriggerHandler`: dispatch
recalculates deal years, per-transaction dedupe, name-only update does not dispatch,
line-item change dispatches through the real trigger. `OpportunityChangePublisherTest`:
no-payload-change save publishes nothing and runs zero queries; stage change publishes;
repeat save reuses caches (zero queries). `OpportunityBillingEntityHandler_Test`: second
renewal in-transaction hits the previous-opp memo.

Coverage (KJDEV run): OpportunityHandler 100%, ProcessLineItems 93%, ChangePublisher 98%,
TriggerHandler 89%, AnalyticsCreate 86%, BillingEntityHandler 80%.

## Measurement gotchas (for the next league table)

- `sf apex run` **overrides the user TraceFlag** with its own debug header (no `DB`
  category) — zero SOQL events. Use a plain REST PATCH (`sf data update record`) so the
  TraceFlag's DebugLevel governs; `OF_SOQL_Audit` (`7dlPx0000000p2XIAQ`) is the level.
- `Approval.isLocked/lock/unlock` do **not** emit `SOQL_EXECUTE_BEGIN`, so the lock fix is
  invisible to this metric (it shows up in the row-limit ledger instead); the counted
  before/after numbers understate the total win.
- Only one TraceFlag window per user — reuse/update an expired flag row rather than creating
  a new one.

## Rollback

Each class reverts independently (git history on this branch holds the pre-change PROD
retrievals in the parent commit). The CMDT `Default` record can be re-activated in Setup.
No schema, flow, or picklist changes are part of the behaviour path (the two parity syncs
are sandbox-only).
