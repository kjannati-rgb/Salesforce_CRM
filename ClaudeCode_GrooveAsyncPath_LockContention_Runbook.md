# Groove Async-Path Lock Contention — Diagnosis Runbook

_Author: Claude Code · Read-only diagnosis in LBR_PROD (via read-only connector) · 2026-08-07_

## 1. Incident as reported

Three concurrent async interviews of `Opportunity_AfterUpdate_MasterFlow` (Async Path) called the
subflow `Opportunity_Update_Opportunity_with_Flow_Data_groove` on 2026-08-07 around 16:35, all
failing at `Update_Opp_with_PCR_Task_Data` with:

```
UNABLE_TO_LOCK_ROW: unable to obtain exclusive access to this record or 3 records:
0016g00001AQH4XAAX, 0016g00001EYGNXAA5, 0016g00001EYHoUAAX
```

Affected Opportunities: `006Px00000Q5fy3IAB` (Bartlit Beck LLP – GCC Midwest 2026),
`006Px00000Q5fy7IAB` (CMBG3 Law – GCC Midwest 2026), `006Px00000Q5gE5IAJ` (Davis Wright Tremaine –
Wipl 2026). Salesforce Error ID `1919378155-63112 (-533548092)`.

## 2. What was verified (read-only, PROD)

**The three locked IDs are each Opportunity's own parent `AccountId` — not a shared account.**

| Opportunity | AccountId (locked) | Account Name |
|---|---|---|
| 006Px00000Q5fy3IAB | 0016g00001AQH4XAAX | Bartlit Beck LLP |
| 006Px00000Q5fy7IAB | 0016g00001EYGNXAA5 | CMBG3 Law, P.C. |
| 006Px00000Q5gE5IAJ | 0016g00001EYHoUAAX | Davis Wright Tremaine LLP |

This rules out the "3 opps racing for 1 shared account" framing from the original triage — each
interview only needed its **own** account, so the contention is with a *different* concurrent
process per account, not the other two interviews.

**All three Opportunities — and several siblings on the same three accounts — were bulk-edited by
Kam today, 15:28–15:38 UTC**, via a rolling operation (not one atomic transaction):

- Bartlit Beck LLP: 3 opps touched (15:32:47, 15:34:01, 15:36:26)
- CMBG3 Law: 3 opps touched (15:28:58, 15:29:16, 15:32:47)
- Davis Wright Tremaine: 7 opps touched (15:32:26 → 15:36:28)

`Flow_Log__c` confirms `Opportunity_AfterUpdate_MasterFlow - Async Path` already ran **successfully,
with no error, for these exact 3 records at 15:32:46 and again at 15:35:01** — i.e. the async path
was invoked multiple times for the same records within minutes, consistent with Salesforce
re-evaluating/retrying scheduled-path work during a bulk-edit window. No `Flow_Log__c` row exists
for a ~16:35 attempt — that failed transaction rolled back before its own log write committed.

**`Async_Path` is configured with `maxBatchSize = 5`, firing 2 minutes after each record's own
`LastModifiedDate`** (`force-app/main/default/flows/Opportunity.flow-meta.xml`, start element,
`scheduledPaths` → `Async_Path`). With ≥13 opportunities across just these 3 accounts becoming due
within an ~8-minute window, Salesforce necessarily queued multiple 5-record batches — and under that
queue depth, actual execution can (and did) slip well past the nominal 2-minute offset, landing at
~16:35, roughly an hour after the triggering saves.

**The Groove fields are not "still blank" — they already hold the correct, best-available data:**

| Opportunity | Flow_Name__c | Step_Number__c | Step_Type__c | Template_Name__c |
|---|---|---|---|---|
| 006Px00000Q5fy3IAB | null | 2 | Auto-Sent Email | null |
| 006Px00000Q5fy7IAB | null | 2 | Auto-Sent Email | null |
| 006Px00000Q5gE5IAJ | null | 2 | Auto-Sent Email | null |

`Update_Opp_with_PCR_Task_Data` writes all 4 fields from a single Task in one `recordUpdate` — a
partial result only exists if an *earlier* run already committed. Tracing the flow's own matching
logic (`Get_PCR_Flow_Task`: most recent `groove_sent_from_flow__c` Task on the contact with
`CreatedDate <= Opportunity.CreatedDate`) against the 3 contacts confirms the matched source Task in
every case is an October 2025 task whose own `Flow_Name__c`/`Template_Name__c` are blank. **The flow
is working correctly; the source Task data is genuinely incomplete, so `Groove_Last_Flow_Name__c`
will stay null indefinitely** — which also means `Run_Flow`'s entry gate (`IsNull(Groove_Last_Flow_Name__c)`)
**never closes for these 3 records**, so every future edit will re-trigger this same subflow attempt
again, forever.

## 3. Root cause

**Structural, not a one-off data-load fluke:** `Async_Path`'s `maxBatchSize = 5` plus
`RecordField`-timeSource scheduling means any bulk edit touching more than a handful of Opportunities
in a short window creates many small concurrent batches, whose actual execution time is decoupled
from (and can trail) the original save by a wide margin. Three of today's batches happened to land at
the same moment while separately processing sibling Opportunities of Bartlit Beck, CMBG3, and Davis
Wright Tremaine — each batch's interview needing a write near its own account row lost the race
against another concurrent process on that same account (most likely another sibling opportunity's
interview further along in the same master flow, e.g. a Task-creating step later in the path that
synchronously updates the Account via `Task_AL__FirmUpdate`'s "Update Firm" action — this specific
link is plausible from the metadata but **not confirmed from a log/trace**; flagged as an open item
below).

**Compounding factor, not the trigger:** these particular 3 Opportunities can never satisfy
`Run_Flow`'s exit condition (source Task data is permanently incomplete), so they re-attempt this
subflow on every future touch — indefinitely re-exposing them to the same lock-contention window
whenever another bulk edit hits their accounts.

**Ruled out:** the FSS (`Firm Sales Summary`) rollup engine (`OpportunityFirmRollupHelper` →
`FirmRollupQueueable`/`FirmRollupService`) writes to `Ultimate_Account__c`, which is a *different*,
higher-level Account for all 3 firms than the locked `AccountId`s — it is not the direct locker here.

## 4. Remediation

**No backfill is needed.** The 3 Opportunities already carry exactly the data the flow would write if
it succeeded (Step 2 / Auto-Sent Email / Name+Template null) — that's what the underlying Task
actually has. There is nothing meaningful to recover; the fault was a lock collision on an
already-a-no-op write.

**Recommended:** no production write. Confirm with the user before taking any action.

## 5. Structural recommendations (for discussion, not applied)

1. **Widen `Async_Path`'s `maxBatchSize`** (5 → a larger value, e.g. 50–200) to reduce the number of
   concurrent small batches spawned by future bulk edits. This is the most direct lever on the
   observed contention.
2. **Close the permanent-retry loop**: change `Run_Flow`'s gate so records whose matched source Task
   has a genuinely blank `Flow_Name__c` don't keep re-qualifying — e.g. also stamp a
   "Groove_Match_Attempted__c" flag, or check that flag instead of `IsNull(Groove_Last_Flow_Name__c)`,
   so records like these 3 stop re-entering the subflow on every future edit.
3. **Retry-on-lock**: if the fault path can distinguish `UNABLE_TO_LOCK_ROW`, a single automatic retry
   after a short delay (Apex-side, since Flow has no native retry-with-backoff) would absorb this
   class of transient contention without needing a wider batch size change.
4. **Confirm/trace `Task_AL__FirmUpdate`'s actual concurrency** with the sibling-opportunity theory
   above — pull debug logs or `Flow_Log__c` (extend logging to fault paths, since currently only the
   entry point is logged) for the next occurrence to nail the exact colliding writer.

## 6. FULLUAT validation (2026-08-07)

Both fixes deployed to FULLUAT (Deploy ID `0AfAd00000SIRPpKAP`, alongside the pre-existing
`Platform_Fault_Logger` + `Fault_Alert_Setting__mdt` dependency gap that blocked the deploy — see §7)
and validated against a 10-record bulk touch on Bartlit Beck LLP (`0016g00001AQH4XAAX`), the same
account from the original incident (FULLUAT is a full copy sandbox, so record IDs match PROD):

- **`maxBatchSize` fix confirmed**: all 10 `Async Path` interviews ran in a single batch
  (`Interview_Start_Time__c = 20:13:01` for all 10) — under the old `maxBatchSize = 5` this would have
  split into 2+ batches, which is the mechanism that caused the original contention.
- **Retry-gate fix confirmed**: the one seeded record already carrying a partial write
  (`Groove_Last_Flow_Step_Number__c = 3`, `Flow_Name__c` still null — the exact "stuck forever" shape
  from the incident) was **not** re-updated by the subflow (`LastModifiedDate` unchanged from the bulk
  touch), confirming the new dual-null gate correctly excludes it going forward.
- **Zero faults**: all 22 `Flow_Log__c` rows from the test have `Error_Description__c = null`.
- One untouched record found no task match and got a harmless null-value re-write, cascading into one
  extra Sync+Async round — expected flow re-trigger behavior, not a defect.

## 7. PROD go-live (2026-08-07)

**Discovered a blocker on the standard deploy path:** the committed `Opportunity.flow-meta.xml`
bundles the `maxBatchSize` fix together with the 2026-06-13 Centellic fault-handling change (commit
`e6120ec`), which was deployed to KJDEV only — its own commit message flagged **"REVIEW NEEDED:
approval submits now log-and-continue vs abort - business sign-off before prod"**, and that sign-off
was never given. The same commit also silently drops the `Create_OA_record` subflow call
(`Opportunity_analytics_product_added`) from the execution path — a functional removal, not just
reliability work. Deploying the file as-is would have shipped both, unreviewed, as a side effect of
the lock-contention fix.

Verified PROD's actual active version (29, fetched via Tooling API) doesn't match either git commit
exactly — it has neither `Log_Master_Fault` nor `Create_OA_record`, meaning PROD has genuine drift
from git history. **Reconstructing from git commits would have risked silently reviving a removed
element in production** — ruled out for that reason.

**Resolution — isolated the fix from the bundle:**
1. `Opportunity_Update_Opportunity_with_Flow_Data_groove` (retry-gate fix, no dependency on the
   bundle) deployed and activated standalone — version 2, active in PROD.
2. `Platform_Fault_Logger` + `Fault_Alert_Setting__mdt` (+3 fields, `Default` record) installed and
   activated in PROD as a genuine, already-committed dependency gap (same as FULLUAT's) —
   `Alert_Enabled__c = false`, so no alert emails fire. This does **not** activate the Centellic
   fault-handling *behavior* on the master flow; it only makes the logger available for when/if that
   behavior is ever approved.
3. `Opportunity` master flow: rather than activate the bundled draft (v30), Kam hand-edited PROD's
   *actual* active version (29) directly in Flow Builder — Async Path Batch Size 5→50, Save As new
   version (31) — bypassing the reconstruction-from-git risk entirely. Verified via Tooling API diff
   before activating: **only 4 lines differed** between v29 and v31 (record Id, `status` Active→Draft,
   and `maxBatchSize: 5→50`) — no stray canvas-position drift from Auto-Layout, no reappearance of
   `Create_OA_record`. Activated as version 31.
4. The bundled draft (v30) remains in PROD as an inert, never-activated version — harmless, nothing
   points to it.

**Net effect in PROD:** both intended fixes are live; the Centellic fault-handling change remains
exactly where it's always been — unshipped, pending the business sign-off its author called for.

**FULLUAT correction:** the earlier FULLUAT deploy (§6) auto-activated the full bundle, since FULLUAT
(unlike PROD) deploys flows as active by default — this was a mirror of the same problem, not caught
until reviewing the PROD activation. Same isolation treatment applied there: v32 (FULLUAT's
pre-Centellic baseline, Obsolete) hand-edited the same way (Async Path Batch Size 5→50, Save As new
version → 34). Diffed v32 vs v34 via Tooling API before activating: Auto-Layout reflowed nearly every
element's `locationX`/`locationY` (cosmetic canvas positions only, confirmed by identical element
count — 134 = 134 — and zero non-location/non-expected diff lines), plus the intended
`maxBatchSize: 5→50`. Activated v34 — **FULLUAT's Opportunity flow now matches PROD's actual shipped
state**, a genuine UAT mirror again, not carrying an unreviewed feature the real target environment
doesn't have.

**State as of this point:**

| Org | Opportunity master flow active version | Groove subflow | Platform_Fault_Logger |
|---|---|---|---|
| PROD | 31 (v29 baseline + `maxBatchSize` only) | v2 (retry-gate fix) | Installed, dormant |
| FULLUAT | 34 (v32 baseline + `maxBatchSize` only) | active (retry-gate fix, §6) | Installed (from §6) |

Neither org ran the Centellic fault-handling bundle or `Legal_Vertical_tasks`/`Opp_SB_CustomerJourney2`
at this point — see §8 for what changed once sign-off was given.

## 8. Centellic sign-off given — full bundle activated (2026-08-07)

Business approval given for the 2026-06-13 Centellic fault-handling change. Rather than rebuild from
scratch, activated the bundled draft (v30) already sitting inert in PROD from §7 — it already contains
`maxBatchSize` + Centellic fault-handling + one more piece surfaced during review: a
`Legal_Vertical_tasks` element calling `Opp_SB_CustomerJourney2`, present in git's baseline (predates
even the Centellic commit) but never wired into PROD's live master flow.

**Correction on an earlier claim:** this runbook's PROD validation step recalled a "no active version"
warning for `Opp_SB_CustomerJourney2` and initially treated it as a PROD fault risk. That warning was
actually from the FULLUAT deploy report, not PROD's — confirmed via direct query that
`Opp_SB_CustomerJourney2` **is** active in PROD (v6). Activating v30 there does not fault.

**PROD:** activated v30 directly (Deploy ID confirms `ActiveVersionId` = v30's Flow Id). Both the
approved Centellic behavior and `Legal_Vertical_tasks` are now live.

**FULLUAT — genuine parity gap found:** `Opp_SB_CustomerJourney2` was sitting at **version 9 in Draft**
there since 2026-06-20, unlike PROD's active v6 — meaning `Legal_Vertical_tasks` genuinely would have
faulted in FULLUAT specifically (the PROD concern above, misattributed at the time, turned out to be
real for this org). Activated `Opp_SB_CustomerJourney2` v9 first, then diffed it against PROD's active
v6: only a cosmetic description-text change (no functional difference), so no re-authoring was needed.
Then activated the equivalent Opportunity bundle (v33) in FULLUAT.

**Final state, both orgs — full parity:**

| Org | Opportunity master flow | `Opp_SB_CustomerJourney2` | Groove subflow | Platform_Fault_Logger |
|---|---|---|---|---|
| PROD | v30 (full bundle, approved) | v6, active | v2 | Installed |
| FULLUAT | v33 (full bundle, approved) | v9, active (content-equivalent to PROD's v6) | active | Installed |

## 9. Branch reconciliation (2026-08-07)

Separately from the flow work: `create-contact-from-user-v4` (where all of this session's commits
landed — it was simply the checked-out branch when the session started, not a deliberate choice) had
drifted ~50 commits ahead of `salesforce-opp-automation` (the designated main/PR branch), holding
real, already-deployed work — FSS, REV-71, attorney-field-consolidation, Centellic emails, ChurnZero,
and this fix — none of it ever merged back. Meanwhile `origin/salesforce-opp-automation` had 2 commits
of its own (`Opportunity_Team_Member_Stamp_Role_Fields` / CED-SDR stamp work) that
`create-contact-from-user-v4` never had.

Verified zero file overlap between the two histories before merging (confirmed via 3-way merge-base
diff, not just branch names). Merged both into `salesforce-opp-automation` via an isolated git
worktree — the session's own uncommitted WIP on `create-contact-from-user-v4` was never touched — and
pushed to origin as a clean fast-forward (no force, no conflicts). `salesforce-opp-automation` now
reflects deployed reality.

## 10. Open items

- The exact mechanism forcing the Account-row lock during `Update_Opp_with_PCR_Task_Data` (an
  Opportunity-only DML) was not directly observed in a trace — the sibling-interview /
  `Task_AL__FirmUpdate` theory is the best-supported hypothesis from the metadata and timing evidence,
  not a confirmed causal chain.
- Not checked: whether other accounts/opportunities across the org hit the same pattern today (this
  diagnosis was scoped to the 3 reported IDs and their siblings on the same 3 accounts).
- **Centellic fault-handling change (`e6120ec`) remains blocked on business sign-off** — unrelated to
  this incident, but discovered as a side effect of this deploy. Still sitting on `Opportunity` v30 in
  PROD (inert) and in git HEAD. Needs its own review track before any future deploy of this flow
  file accidentally carries it live again.
- **Process gap**: Salesforce Flow deploys are whole-version, not line-level — there's no clean way to
  ship one committed change from a flow file without shipping everything else committed alongside it.
  Worth adopting the kill-switch/CMDT-gating pattern already used elsewhere in this codebase (e.g.
  REV-71's `Layer 1/2 Active` switches) for flow changes that need to land in source ahead of their
  business approval, so activation isn't the only lever separating "committed" from "live."
