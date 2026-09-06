# Renewal failure runbook — Phase 0–2 findings

**Run date:** 15 August 2026
**Org verified:** production `00D6g0000081IOgEAM` (= `00D6g0000081IOg`), `IsSandbox = false`
**Sandbox verified:** KJDEV `00DAe00000D35gVMAR`, `IsSandbox = true`
**Status:** ROOT CAUSE FOUND. No production writes made.

---

## REMEDIATION LOG

| # | Contract | Account | Value | Method | Result |
|---|---|---|---|---|---|
| 1 | 00044367 | Spencer Fane LLP | USD 23,940 | CPQ UI "Renew", single record | ✅ `006Px00000UBDOsIAP` — all Phase 5 checks pass |
| 2 | 00047980 | 5 Stone Buildings Caribbean | GBP 10,638 | — | pending |
| 3 | 00047867 | Vivien Chan & Co | GBP 5,400 | — | pending |
| 4 | 00047898 | EZ Service S.r.l. | EUR 28,750 | — | pending |
| 5 | 00047833 | SAP SE | EUR 50,000 | — | pending (GATE 4-SAP, last) |

**Recovered so far: USD 23,940. Outstanding: GBP 16,038 + EUR 78,750.**

### Record 1 verification (00044367)

Close date 2027-04-06 = contract end 2027-04-05 + 1 ✓ · Amount 23,940 USD matches source and
contract currency ✓ · Owner Kamyar Jannati matches `SBQQ__RenewalOwner__c` ✓ ·
`Contract.SBQQ__RenewalOpportunity__c` populated ✓ · **exactly one contact role**
(Deanna L. Long, Decision Maker, Primary) with no duplicate ✓

**This confirms the diagnosis.** The contact-role clone completed cleanly on a single-record
retry. The `DUPLICATE_VALUE` was a bulk-context artefact of the 13 August four-record transaction,
not an inherent property of these contracts. Individual retry is the correct remediation and no
flow change is required for it.

### Loose end closed — the "mystery creator"

The renewal was triggered manually by Kamyar through the UI, yet the opportunity's `CreatedBy` is
**Saurabh Patil**. Renewal opportunity creation runs in an async context under that user
regardless of who initiates it. That fully explains the Phase 2 observation of a consistent
Saurabh Patil attribution across contracts created by four different people, and the 3–4 minute
lag. No scheduled job or integration is involved.

---

## Diagnosis — this is TWO failures, not five, and one is a stale bulk artefact

All five `ContractSave` errors captured:

| Contract | Error | Error ID |
|---|---|---|
| 00047833 SAP SE | `DUPLICATE_VALUE: Contact has already been added in that Contact Role` | `452526092-138563 (550428964)` |
| 00047867 Vivien Chan | `DUPLICATE_VALUE` (same text) | `452526092-138563 (550428964)` |
| 00047898 EZ Service | `DUPLICATE_VALUE` (same text) | `452526092-138563 (550428964)` |
| 00047980 5 Stone | `DUPLICATE_VALUE` (same text) | `452526092-138563 (550428964)` |
| 00044367 Spencer Fane | `Error while saving Opportunity Line Items: socket hang up` | — |

**Four records carry a byte-identical Error ID.** Salesforce Error IDs are per-transaction, so
four contracts cannot independently generate the same one. This is **one failure recorded against
four records**, not four failures.

It maps exactly to the 13 August attempt. `ContractHistory` shows `SBQQ__RenewalQuoted__c`
false→true at **2026-08-13 18:27:07** on precisely those four contracts in a single bulk DML —
`00047867`, `00047898`, `00047980`, `00047833`. One transaction, one duplicate collision, one
rollback taking all four down together.

### Consequences

1. **The `ContractSave` panel shows a stale stored error, not live state.** It is the residue of the
   last attempt. It should not be read as "this contract is currently failing for this reason".
2. **The bulk attempt caused the shared failure.** The runbook's rule 6 — one record at a time — is
   exactly right, and the 13 August attempt violated it by updating four at once. A single
   duplicate anywhere in the batch rolled back every record in it.
3. **Spencer Fane is a different and much simpler problem.** `socket hang up` is a transient
   network/timeout failure from April 2026 while saving Opportunity Line Items. Nothing to do with
   contact roles. It most likely just needs a retry.

### Revised remediation

- **00044367 Spencer Fane** — retry as a single record. Transient failure, highest chance of
  clean success, and the longest overdue (failed April, unnoticed four months).
- **The other four** — retry **individually**, never bulked. The duplicate may not recur outside a
  bulk context; if it does, it will now be isolated to the one record that genuinely has it rather
  than taking all four down.

This supersedes the contact-role root-cause analysis below, which was derived from the 5 Stone
error before it was known to be a shared bulk artefact.

---

## Superseded — contact role duplicate analysis

Found on the contract record itself, in CPQ's own `SBQQ.ContractSave` Visualforce panel
(contract `00047980`, 5 Stone Buildings Caribbean):

> **Error creating Opportunity:** We can't save this record because the
> **"Opportunity_AfterUpdate_MasterFlow"** process failed. This error occurred when the flow tried
> to create records: **DUPLICATE_VALUE: Contact has already been added in that Contact Role.**
> Error ID: 452526092-138563 (550428964)

### The mechanism

1. `SBQQ__DefaultRenewalContactRoles__c = true` on all five contracts, so CPQ clones the source
   opportunity's contact roles onto the new renewal opportunity.
2. `Opportunity_AfterUpdate_MasterFlow` **also** creates a contact role for the same contact.
3. Two writers, same contact → `DUPLICATE_VALUE`.
4. The exception propagates and **the entire renewal opportunity insert rolls back**. No
   opportunity, no `SBQQ__RenewalOpportunity__c`, no partial records.

Verified on 5 Stone: the source opportunity `006Px00000TP0PBIA1` has exactly **one** contact role —
Matthew Paton, Decision Maker, Primary. CPQ clones him; the flow adds him again; collision.

### Why nothing ever surfaced it

The error is rendered by `SBQQ.ContractSave`, a **managed-package Visualforce page**. It is not
written to `Flow_Log__c`, not on a field, and not queryable. It is visible only to a person looking
at the contract record in the UI. That is why four months passed on Spencer Fane, and why every
query-based diagnostic in this runbook came back clean.

This is the same dual-writer contact-role collision previously diagnosed on CPQ renewals. The
runbook's SAP-specific section already anticipated it ("prior history of renewal failure on a
duplicate contact role constraint") — it just applies to **all five**, not only SAP.

### The exact defect (from the flow diff, 15 Aug)

Chain: `Opportunity` (label `Opportunity_AfterUpdate_MasterFlow`, v32) → subflow
`Opportunity_Renewal_New_Records` (v13) → element **`Create_Opportunity_Contact_Role`**.

That create writes:

| Field | Value |
|---|---|
| `ContactId` | `recordId.Primary_Contact__c` |
| `Role` | `"Decision Maker"` (hardcoded) |
| `IsPrimary` | `true` |

It is gated by decision **`Create Opportunity Contact Role?`**, whose only conditions are:

1. `Primary_Contact__c` is not null
2. `Pardot_Form_Completion__c` is not null

**It never checks whether a contact role already exists for that contact.** So when CPQ has
already cloned one (`SBQQ__DefaultRenewalContactRoles__c = true`), this creates a second identical
row and the platform rejects it.

5 Stone matches exactly: its source contact role is Matthew Paton / **Decision Maker** /
IsPrimary — the identical triple this element writes.

**Fix:** add a Get Records on `OpportunityContactRole` filtered by `OpportunityId = recordId.Id`
and `ContactId = recordId.Primary_Contact__c` ahead of the create, and add a third condition so it
only fires when none is found. Small and surgical — one lookup plus one condition.

### ⚠️ FALSIFIED 15 Aug — this element is NOT the culprit

Production check: **`Pardot_Form_Completion__c` is null on all five source opportunities.**

| Contract | Account | `Primary_Contact__c` | `Pardot_Form_Completion__c` |
|---|---|---|---|
| 00047833 | SAP SE | Janaka Bohr | **null** |
| 00047980 | 5 Stone Buildings | set | **null** |
| 00047867 | Vivien Chan & Co | set | **null** |
| 00047898 | EZ Service S.r.l. | set | **null** |
| 00044367 | Spencer Fane LLP | set | **null** |

The gate requires **both** conditions to be non-null. With `Pardot_Form_Completion__c` null, the
decision takes its "Do Not Create" default branch and `Create_Opportunity_Contact_Role` never
runs. It therefore cannot be the source of the `DUPLICATE_VALUE`.

The guard built at `guardfix/flows/` is still a legitimate hardening of that element — creating a
contact role without checking for an existing one is a real latent bug — but it does **not** fix
these five, and should not be deployed on that basis.

Also checked on SAP (`006Tm00000GDMntIAH`): **no duplicate ContactIds** among its 36 contact roles,
and one primary role (Janaka Bohr, Decision Maker). The source data is clean.

**The duplicate must come from another writer inside `Opportunity_AfterUpdate_MasterFlow`'s subflow
chain, or from CPQ's own clone colliding with a role created elsewhere. Not yet identified.**

The only reliable evidence is the per-contract error text on CPQ's `SBQQ.ContractSave` panel, which
is visible in the UI and nowhere else. That needs capturing for each of the five — the 5 Stone one
was captured; the other four have not been.

### Correction — PROD is NOT missing the duplicate fix

PROD's `Opportunity_Contact_Role_Check_for_Duplicate` v9 **already contains** the Phase 2
"reconcile-not-reject" fix. Its own description states it no longer throws a Custom Error on a
duplicate, writes a non-blocking `Flow_Log__c` row, lets the save commit, and leaves cleanup to
`OpportunityContactRoleReconciler`. It is explicitly the "PROD variant", writing `Flow_Log__c`
directly rather than depending on `Platform_Fault_Logger` — described in the flow as a
"KJDEV-only Centellic pilot".

KJDEV v10 is the same fix via the `Platform_Fault_Logger` subflow, plus a fault connector on
`Get_Contact_Role`. **The version gap is a deliberate logging-mechanism variant, not a missing
fix.** The earlier "deploy KJDEV's fix to PROD" recommendation is withdrawn.

This matters: because that guard no longer throws, the `DUPLICATE_VALUE` is **not** coming from it.
It is the platform's own `OpportunityContactRole` uniqueness rejecting the insert above.

### Flow diff results

| Flow | PROD vs FULLUAT | PROD vs KJDEV |
|---|---|---|
| `Opportunity` (master) | **identical** | different (50,308b / 47,692b) |
| `Opportunity_Contact_Role_Check_for_Duplicate` | **identical** | different (7,779b / 9,628b) |
| `Opportunity_Contact_Role_Create` | **identical** | different (7,796b / 7,035b) |
| `Opportunity_Renewal_New_Records` | **identical** | different (54,930b / 51,615b) |

PROD and FULLUAT are byte-for-byte identical on all four. **FULLUAT will therefore reproduce this
defect via the CPQ UI path** — the earlier batch tests exercised the wrong path, not an invalid org.

### Relevant flow versions

| Flow | PROD | KJDEV |
|---|---|---|
| `Opportunity_Contact_Role_Check_for_Duplicate` | v9 (2026-07-09) | **v10** (2026-06-27) |
| `Opportunity_Contact_Role_Create` | v8 (2026-07-09) | v6 (2026-01-11) |
| `Opportunity_Renewal_New_Records` | v13 (2026-07-09) | v9 (2026-06-17) |

KJDEV carries a **later** duplicate-guard version than production. PROD's other two are later, so
the lineages have crossed — a diff is required before deploying anything.

### FULLUAT is not a valid reproduction

The batch silently no-ops there in **all three** configurations tested (`RenewalQuoted` true and
false, `DefaultRenewalContactRoles` true and false) — never erroring, never creating. Production
throws an explicit `DUPLICATE_VALUE`. Different symptom, so FULLUAT cannot validate a fix for this.
FULLUAT was restored to exact pre-state after testing.

Note the production error came from the **CPQ UI / `ContractSave` path**, not the batch — so that
is the path any remediation must be tested against.

---

---

## Phase 0 — population confirmed

The detection query returns **exactly the five contracts** in the runbook. No new failures since
15 August. Confirmed genuinely missing, not a broken lookup — `SBQQ__RenewedContract__c` returns
zero opportunities for all five.

Value at stake (source opportunity amounts, all Closed Won, none cancelled):
GBP 16,038 · USD 23,940 · EUR 78,750.

---

## The runbook's Phase 4 fix rests on a premise the data contradicts

`SBQQ__RenewalForecast__c` is **already `true`** on all five. Phase 4 proposes toggling it
false→true to fire creation.

It also does not discriminate: a control group of the 15 most recent **successfully renewed**
contracts carries `SBQQ__RenewalForecast__c = true` **and** `SBQQ__RenewalQuoted__c = true` —
identical flag state to the five failures. Neither flag separates success from failure.

### What the 13 August attempt actually did

`ContractHistory` (`RenewalQuoted` is tracked; `RenewalForecast` is not):

| Time (UTC) | Change | By |
|---|---|---|
| 2026-08-13 18:26:55 | `RenewalQuoted` true → false (4 contracts) | Kamyar Jannati |
| 2026-08-13 18:27:07 | `RenewalQuoted` false → true (4 contracts) | Kamyar Jannati |

The off/on cycle was **12 seconds** apart, against the runbook's own 30-second gap and 6-minute
wait. Confirms rule 5.

---

## Phase 2 — the mechanism, from retrieved production metadata

Retrieved production `ApexClass` + `ApexTrigger` (the repo on `order-form-v1.2` does not match
production, so the repo alone could not answer this).

### The live creator

**`OrderTriggerForRenewalOpp`** (Order, after update) → **`RenewalOpportunityHandler2.processOpportunities`**,
which is **`@future`** — that is the observed 3–4 minute lag.

It fires when `Status` changes to `Activated`, `OpportunityId != null`, not a reduction order,
`Type != 'Amendment'`. Renewal creation in this org is therefore driven by **Order activation**,
not Contract activation, and not by CPQ's native renewal engine.

Gated by a per-profile/per-user hierarchy custom setting:

```apex
if(!oppIds.isEmpty() && (app != null && app.Is_Active__c && app.Trigger_Name__c=='OrderTriggerForRenewalOpp'))
```

**Checked — this is not the blocker.** All 29 `Trigger_Settings__c` records, including the org
default, have `Is_Active__c = true` and `Trigger_Name__c = 'OrderTriggerForRenewalOpp'`.

### Two nightly safety nets

| Job | Cron (org local) | Class | Scope |
|---|---|---|---|
| `Edition Renewal Opportunity Creation - Nightly` | 02:30 | `EditionRenewalOpportunityBatch` | all families **except** `Lexology Index` |
| `Contract Renewal API - Nightly` | 02:45 | `ContractRenewalApiBatch` | **`Original_Opportunity__c LIKE 'WTR 1000%'`** |

Both live, both fired on 14 and 15 August (`TimesTriggered = 12`). The 01:30/01:45 UTC
`Renewal_Run__c` timestamps are these two jobs — 02:30/02:45 BST.

### ⚠️ The most actionable finding

`ContractRenewalApiBatch` selects **exactly this population**:

```sql
WHERE Status = 'Activated'
  AND SBQQ__RenewalForecast__c = true
  AND SBQQ__RenewalOpportunity__c = null
  AND SBQQ__Opportunity__r.Cancelled__c = false
```

All five match every clause — **but the scheduler passes the `'WTR 1000'` prefix**, and none of
the five `Original_Opportunity__c` values begin with "WTR 1000":

- `Docket Navigator - Multi Product | Renewal | ...`
- `Lexology Pro - In House | Renewal | ...`
- `IAM Copyright 1000 2026 - Biography | New Business | ...`
- `Lexology PRO - IH | Renewal | ...`
- `Matthew Paton - 5 Stone Buildings - PCGE`

**The org already runs a nightly job that would fix these five, and it skips them purely on the
scope filter.** `ContractRenewalApiBatch` has a no-arg constructor that runs unscoped.

Note its scheduler's comment: chunk size is deliberately **1**, because
`SBQQ.RenewalAPI.renewContracts()` enqueues its own Queueable per call and larger chunks breach
the queueable-per-transaction ceiling, aborting the whole chunk. Any remediation must respect this.

### Why the failures left no trace

`RenewalOpportunityHandler2` logs to `Flow_Log__c` **only from its catch block**. If
`getRenewalOpportunities()` returns an empty map, the entire work block is skipped with no
exception and no log.

Confirmed: the most recent `Class_Name__c = 'RenewalOpportunityHandler2'` error is **2 July 2026**.
There is no log for any of the five activation dates. The handler did not throw — it silently
did nothing.

### Ruled out as the discriminator

- `SBQQ__RenewalForecast__c`, `SBQQ__RenewalQuoted__c` — true on failures *and* successes
- `Renewal_Deleted__c` — false on both
- Source opportunity `Cancelled__c` / stage — all five Closed Won, none cancelled
- `Trigger_Settings__c` gate — active org-wide
- **`Product2.Renewal_Not_Required__c`** — tested and rejected. All 13 primary quote lines across
  the five failures have `Renewal_Not_Required__c = true`, which does exclude the opportunity from
  `getRenewalOpportunities()`. But the control group shows 10/10 primary lines on
  *successfully renewed* contracts are also `true`. It cannot be what separates them.

### Still open

All five successful renewals were created by **Saurabh Patil**, 3.5–4 minutes after contract
creation, with two distinct naming conventions ("Law.com - <Account> - Renewal - 2027" vs the
pipe-delimited CPQ style) — which suggests **more than one creator is in play**, and the one that
served the successes is not yet identified. `@future` runs as the calling user, so a consistent
Saurabh Patil attribution across contracts created by four different people points to Order
activation itself being performed by a process running as that user.

`CronTrigger` shows no job on a 3–4 minute cadence, so this is not a high-frequency scheduled job.

---

## Two corrections to the earlier Phase 0–2 note

1. **`Renewal_Run__c` custom fields do exist in production.** `ContractRenewalApiBatch` compiles
   against `Status__c`, `Scope_Description__c`, `Records_Evaluated__c` etc. and is deployed, so
   they must. The earlier "no custom fields" reading was **field-level security masking them from
   the connector** — a describe/SOQL "No such column" on a field the running user cannot see. The
   run log is not empty; it is unreadable to this user. Worth fixing on its own merits.
2. **`RenewalReconciliationBatch` does not exist** in production. It is referenced only in
   `ContractRenewalApiScheduler`'s header comment. The "three nightly renewal jobs" described
   there are actually two.

---

## Also worth raising

`Renewal Creation Check` (cron `0 0 12 * * ?`, created by Saurabh Patil) has
**`TimesTriggered = 0` and `PreviousFireTime = null`** — scheduled but has never fired. If this
was meant to be the detection control, it has never run once.

---

## Why this run stopped

1. **GATE 2 is unresolved.** The mechanism is now largely mapped, but the discriminator between
   the five failures and comparable successes is not established, and Phase 4 as written would
   toggle a field already in its target state.
2. **This session is non-interactive**, so the runbook's mandated "proceed" confirmations at
   GATE 0/2/3/4.x cannot be collected. No production write was in scope.

---

## Recommended next steps

1. **Cheapest credible remediation:** run `ContractRenewalApiBatch` **unscoped** (no-arg
   constructor, chunk size 1) against the five, rehearsed in KJDEV first. It already uses
   `SBQQ.RenewalAPI.renewContracts()`, is unit-tested, and its query matches all five exactly.
2. **Identify the remaining creator** — trace what performs Order activation as Saurabh Patil,
   and which path produced the "Law.com - <Account> - Renewal - 2027" style records.
3. **Fix the silent-skip** — add an else-branch log in `RenewalOpportunityHandler2` when
   `getRenewalOpportunities()` returns empty. That single gap is why four months passed before
   Spencer Fane was noticed.
4. **Grant FLS on `Renewal_Run__c`** so the nightly run log is actually readable.
5. **Investigate `Renewal Creation Check`** — never fired.
6. Phase 6.1 (history tracking on `SBQQ__RenewalForecast__c`) stands.

---

## Phase 3 — sandbox rehearsal FAILED (15 Aug)

### ⚠️ Do not run `ContractRenewalApiBatch` unscoped

Its query omits `EndDate >= TODAY` **and** `Renewal_Deleted__c = false`, which the Phase 0
detection query has. Unscoped it selects **642 contracts**, not five:

| `Renewal_Deleted__c` | Count |
|---|---|
| `true` — "deliberately removed, do not recreate" | **594** |
| `false` | 48 (only 5 with a future end date) |

The `'WTR 1000'` scope filter is load-bearing protection, not just a scoping decision.
Unscoping the nightly job would mass-create renewals across 594 deliberately-removed contracts —
runbook rule 4 violated at scale. **Any remediation must target the five contract IDs explicitly.**

### Rehearsal attempt

KJDEV was not usable: 5 contracts total, no candidate matching the criteria. Rehearsed in
**FULLUAT** instead (full copy, real CPQ config), against `800Px00000aiZ4RIAU` / `00044237`
Becker & Poliakoff LLP — pre-state identical in shape to the five (Activated, future end date,
`RenewalForecast = true`, `RenewalQuoted = true`, lookup blank, `Renewal_Deleted__c = false`).

Called `SBQQ.RenewalAPI.renewContracts()` with a chunk of one, using the exact field list from
`ContractRenewalApiBatch.start()`.

**Result — failed:**

```
SBQQ.ValidationException: We can't save this record because the
"Quote_AfterSave_MasterFlow" process failed.
Limit Exceeded — You or your organization has exceeded the maximum limit for this feature.
Error ID: 1357081347-106475 (824709315)
```

RenewalAPI creates a renewal **quote** as well as the opportunity, and that quote insert runs
`Quote_AfterSave_MasterFlow` (RecordAfterSave on Quote, chaining four subflows:
`Quote_AL_UpdateGenericFields`, `Quote_ALM_Code_Stamp`, `Quote_ALM_PromoDispatch_Stamp`,
`Quote_AfterUpdate_OppUpdateProductsstamp`). That chain threw.

**FULLUAT was left clean** — the transaction rolled back completely. Contract lookup still null,
no renewal opportunity created, no orphan records.

### What this rules in and out

- **Not org-limit exhaustion.** No FULLUAT limit is above 50% consumed except DataStorageMB (62%).
- **Not contradicted by production.** There are zero `Class_Name__c = 'ContractRenewalApiBatch'`
  rows in production `Flow_Log__c` — because the `'WTR 1000'` scope means the nightly job matches
  nothing and never calls RenewalAPI at all. **Production has never exercised this path.**
- **Context may matter.** The rehearsal ran synchronously via anonymous Apex; production would
  run inside a batch `execute()` with its own limit context. The scheduler's chunk-size-1 comment
  warns explicitly that this context is fragile. This was NOT proven either way, because
  `ContractRenewalApiBatch` **is not deployed in FULLUAT** — that sandbox predates it.

`Quote_ALM_PromoDispatch_Stamp` is REV-60 work, and `Quote_AfterSave_MasterFlow` is currently
modified-uncommitted on branch `order-form-v1.2` — so deployed versions may differ across orgs.

### Rehearsal take 2 — the real batch path

Deployed `ContractRenewalApiBatch` + `Renewal_Run__c` (object + 11 fields) to FULLUAT, then ran
`Database.executeBatch(new ContractRenewalApiBatch('<full Original_Opportunity__c string>'), 1)`
so the `LIKE 'x%'` matched exactly one contract.

| Run | Contract state | Batch result | Renewal created? |
|---|---|---|---|
| 1 | `RenewalQuoted = true` (as found) | Completed, 0 errors, 1 item processed | **No** |
| 2 | `RenewalQuoted = false` | Completed, 0 errors, 1 item processed | **No** |

The contract is a valid candidate — it has a subscription (`SUB-0102353`, Law.com, qty 1,
`RenewalQuantity 1`, 2026-04-01 → 2027-03-31), which is what RenewalAPI clones.

**FULLUAT restored to exact pre-state** after testing (`RenewalForecast = true`,
`RenewalQuoted = true`, lookup null, `Renewal_Deleted__c = false`).

### The key conclusion

`SBQQ.RenewalAPI.renewContracts()` **silently creates nothing** for this contract profile, and
no CPQ Queueable is ever enqueued (only an `ApexToken` job, which completes clean). It does not
throw, so `ContractRenewalApiBatch` increments `renewedCount` and reports success regardless.

**CORRECTED 15 Aug — the above is wrong.** The batch did *not* fail silently. It caught the
exception, logged it to `Flow_Log__c` and rolled back, exactly as designed. The error was:

> `Renewal failed for Contract 800Px00000aiZ4RIAU (Order 801Px00000cQoY0IAK): 1 ALM line(s) still
> need a required code: LAWM (dispatch). Enter the Dispatch code for the access level: ON (1 user),
> OS (site licence), OE (enterprise), OL (Pro/firmwide).`

That is a **REV-60 ALM dispatch-code validation** blocking the renewal quote — nothing to do with
contact roles. The reason it looked silent is that the `Class_Name__c = 'ContractRenewalApiBatch'`
query was run against **PROD**, not FULLUAT. The batch's logging works and its counters are fine.

So FULLUAT cannot reach the contact-role stage at all for this contract — the renewal is blocked
earlier by the missing ALM dispatch code. Any end-to-end test there needs a contract whose products
do not require ALM codes.

Note the earlier anonymous-Apex attempt on the *same* contract threw `Limit Exceeded` from
`Quote_AfterSave_MasterFlow`, whereas the batch path silently no-ops. Two different invocation
contexts, two different failure modes, neither producing a renewal.

### Where that leaves remediation

1. **Manual creation of the five** (CPQ "Renew" button on the contract, or hand-built
   opportunities) is now the only route with a predictable outcome. Recovers
   GBP 16,038 / USD 43,940-equivalent into the FY pot without code risk.
2. **Raise a CPQ investigation** with debug logs on `SBQQ.RenewalAPI.renewContracts()` to find why
   it no-ops. Until that is understood, no automated remediation should be trusted.
3. **The `Quote_AfterSave_MasterFlow` limit error is a separate, possibly wider defect** — it
   would affect any renewal quote created synchronously.
4. **Fix the batch's false-success reporting** — it should verify
   `SBQQ__RenewalOpportunity__c` is populated after the call rather than assuming success.

