# Opportunity Currency-Change Failure — Phase 1 Diagnosis & Phase 2 Target Architecture

**Date:** 2026-06-11 · **Org audited:** LBR_PROD (00D6g0000081IOg, read-only) · **Reference case:** 006Tm00000DBVgwIAH
**Artifacts:** `audit-reports/currency-fault-2026-06/` (Customer_Journey.flow V22 + V21 JSON, Opportunity_Currency_update_screen_flow.flow v6, Flow_log_v3.flow, Opportunity master flow, trigger bodies)

---

## Phase 1 — Diagnosis

### 1.1 What "Customer Journey" actually is

**It is NOT a Process Builder.** `Customer_Journey` is a **record-triggered after-save flow** on Opportunity
(ProcessType `AutoLaunchedFlow`, TriggerType `RecordAfterSave`, RecordTriggerType `CreateAndUpdate`),
22 versions; **V22 activated 2026-06-09** (V21 13-May, V12 23-Feb, V1 09-Sep-2025).
The error wording "the 'Customer Journey' **process** failed" is just the generic
`CANNOT_EXECUTE_FLOW_TRIGGER` message — it names flows the same way.

V21→V22 diff is a one-line fix (the "Renewal Lex Pro contract out" branch's same-record update now
references `Copy_1_of_Create_handshake` instead of `Create_handshake` — previously stamped the wrong
handshake Id). **V22 did not introduce the currency fault.** June 11 was simply the first time the
currency flow was run against this opp (Flow_Log evidence below).

### 1.2 Flow anatomy (active V22)

- **Entry conditions (start element):** `LexPro_present__c = true OR Content_Sub_Present__c = true`. **No
  ISCHANGED / field-change gating whatsoever** — every save of every Lexology-Pro/Content-Subs opp enters.
- **Two paths:** immediate (sync, blocks the save) and a scheduled path "+2 min after LastModifiedDate"
  (renewal-creation logic — async, cannot cause this error).
- **Immediate path, unconditional prefix (runs on EVERY entry before any decision):**
  1. `Check_if_flow_is_disabled` — reads `$Setup.Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` (existing bypass).
  2. `CReate_flow_log_record` — subflow **Flow_log_v3** → 1 DML insert (`Flow_Log__c`).
  3. **Five Group lookups** (Case - Lex PRO, Lex Pro Customer Management, TBRC – BoL, Specialist platforms CJ queue, Specialist platform Managment) — 5 SOQL, used only by some branches but always executed.
- **Main decision `Opp_Stage`** (8 rules, no default connector → silently ends when nothing matches):
  | Rule | Key conditions | Action chain |
  |---|---|---|
  | New Business and Closed Won1 | Forecast=NB, Stage=Closed Won, CJ_run=false, not cancelled (or Type=Upsell) | handshake lookup → emails → create onboarding Case → **update $Record** (CJ_run=true) |
  | Renewal Closed Lost | Type=(Auto-)Renewal, Stage=Closed Lost | task delete → create "lost" Case + email alert |
  | Renewal Closed Won before budget renewal date | Stage=Closed Won(±Cancellation), Budget_Renewal_Date>today | delete "suspend access?" tasks |
  | Cancelled Opp | Cancelled__c=true | query CJ + tasks → delete tasks |
  | **NB just created** | **Stage ∈ (Identify, Qualify, Evaluate)**, CJ_run=false, Customer_Journey__c null, Forecast ∈ (NB, Upsell) | **Create_handshake (`Customer_Journey__c`) → `Update_Records_3` updates $Record** (sets lookup) → recursive full automation re-entry |
  | Renewal Closed won BG | Closed Won + BG product | goto handshake email path |
  | Upsell Closed won | Stage=Closed Won, Forecast=Upsell, CJ lookup set | emails/Cases |
  | Renewal Lex Pro contract out | Stage ∈ (Contract Out, CW–Pending Approval) | create handshake → **update $Record** |
- **DML inventory:** ~15 creates (Cases, Tasks, Customer_Journey__c), 3 deletes, 5 updates — **zero fault connectors anywhere**.
- Invokes **no Apex** (only email-alert actions + Flow_log_v3 subflow) → no scope-stop per protocol.

### 1.3 The currency screen flow v6 (`Opportunity_Currency_update_screen_flow`)

Path taken for the reference opp (primary quote exists):

```
Start → Flow_log_v3 (commits when screen 1 renders) → Get Opportunity → Check_Stage guard
  (blocks only: Closed Won – Pending Approval, Closed Won, Closed Lost, Cancellation - Pending Review)
→ [SCREEN: pick currency]  ← transaction boundary; everything below is ONE transaction:
   1. Update_opportunity_Stage2 : StageName = "Identify"          (Opp DML #1)
   2. Update_Primary_quote      : SBQQ__Primary__c = false        (Quote DML #2)
        ⚠ filter is ONLY SBQQ__Opportunity2__c = recordId → un-flags ALL quotes, not just primary
   3. Update_opportunity_currency2 : CurrencyIsoCode = choice     (Opp DML #3 — faults here)
→ [SCREEN: success]
```

The no-quote path is worse: it **deletes ALL OpportunityLineItems** (`Delete_Opportunity_Products`,
including manually added ones) before changing currency. No fault connector exists on any DML —
any downstream failure surfaces as an unhandled flow error and rolls back the whole post-screen transaction.

Stage-guard gaps: `Closed Won - Cancellation` and `Contract Out` are not blocked.

### 1.4 Reference record state (006Tm00000DBVgwIAH, read 2026-06-11)

| Field | Value |
|---|---|
| Type / Forecast / RecordType | Renewal / Renewal / Renewals |
| StageName | Evaluate |
| CurrencyIsoCode | GBP (change to USD failed, rolled back) |
| Customer_Journey_run__c / Customer_Journey__c | **true** / null |
| LexPro_present__c / Content_Sub_Present__c | false / **true** (CJ entry passes) |
| Cancelled__c | false |
| Budget_Renewal_Date__c / Contract_Start_Date__c | 2026-07-31 (future) |
| SBQQ__PrimaryQuote__c | a1ITm000002BVc1MAG (Q-166707, Draft, GBP, 5,500; only quote) |
| OLIs | 2 × "IAM - Standard - Team License", GBP, both CPQ-synced (`SBQQ__QuoteLine__c` set) |

**Walking V22 against this state: no `Opp_Stage` rule matches on any of the three DMLs**
(`Customer_Journey_run__c = true` blocks the NB branch; stage is never Closed/Contract-Out; not cancelled).
Only the unconditional prefix executes (log insert + 5 Group queries) — per entry, every entry.

### 1.5 Forensic evidence (Flow_Log__c)

- Only 3 log rows exist for this opp — all `"Opportunity: Currency update screen flow"`:
  Anderson 2026-06-11 18:47:51 + 18:48:15 UTC, Jannati 2026-06-11 20:22:01 UTC. These commit before the
  first screen, so they survive the rollback → **3 attempts, all failed in the post-screen transaction**.
- Zero `"Customer journey task"` rows for this opp → every transaction in which CJ entered for this record
  rolled back (its log rolls back with it).
- Org-wide, Customer Journey logged **14,462 entries in the last 7 days** (~2,000/day) → the flow completes
  fine on ordinary single-DML saves. (Also: that volume is log pollution caused by unconditional logging.)
- The opp's last normal edit (2026-06-09 20:17, Anderson) saved successfully.
- `Flow_Log__c.Record_Name__c` is 255 chars and Flow_log_v3 truncates with `LEFT(…,255)` → the
  long-opportunity-name/STRING_TOO_LONG hypothesis is **ruled out**.

### 1.6 Root-cause assessment

Normal saves pass; only the stacked-DML transaction fails, and it fails inside Customer Journey even
though no decision branch matches this record. The differentiator is **cumulative transaction load**:

```
one transaction:
  Opp DML #1 (stage)    → 4 before-save flows, 9 Apex triggers (SBQQ, sbaa, DOZISF, trumpet,
                          Rollup Helper, 3 local), VRs, 8 after-save flows incl. CJ entry #1
  Quote DML #2 (ALL quotes un-primary) → CPQ QuoteBefore/After: un-sync logic, synced-OLI handling,
                          Opportunity.SBQQ__PrimaryQuote__c cleared → ANOTHER full Opp save cycle
                          → CJ entry #2 (+ OLI delete triggers + Rollup Helper rollups, if CPQ unsyncs lines)
  Opp DML #3 (currency) → platform converts/validates OLI prices + full Opp stack again → CJ entry #3
```

Each CJ entry burns 1 DML + ~6 SOQL before deciding to do nothing. CPQ quote automation is notoriously
SOQL-heavy, and this org is already documented to run near SOQL limits on Opportunity saves (split Apex
runs elsewhere). **Leading hypothesis: a cumulative governor limit (SOQL 101 most likely) is breached
during CJ's unconditional prefix on the 3rd Opportunity save cycle** — the limit consumer is the whole
transaction, but CJ is executing when it blows, so the error names Customer Journey. The
"Salesforce Error ID (gack)" format is consistent with a limit/internal failure rather than a data fault.

Secondary candidates (to be falsified in the KJDEV repro): Flow_Log__c insert failure on entry #3;
CPQ rejecting the currency change with synced OLIs present, surfacing through the flow stack.
The Phase 3 repro with debug logs settles this definitively — the structural fixes below are correct
under all three hypotheses.

### 1.7 Full Opportunity automation inventory (production, 2026-06-11)

**Record-triggered flows — active (12):**

| Flow | Trigger | Order | Notes |
|---|---|---|---|
| Opportunity_BeforeSaveFlow | before, C&U | — | local before-save consolidation |
| Check_Completeness_of_Contact_Roles | before, C&U | — | known-buggy (separate workstream) |
| Complete_Customer_Success_Task_validation | before, U | — | |
| Update_Opportunity_Contract_Attached_Field | before, U | — | |
| UltimateAccountBeforeSaving | before, C | — | |
| Opportunity_Prevent_user_from_deleting_opportunities | before delete | — | |
| **Customer_Journey** | after, C&U **+ scheduled +2 min** | (none) | subject of this task |
| Check_Contact_Role_Log_Faults | after, C&U | — | |
| Opp_Error_Saleshandshake | after, U | — | |
| Opportunity_Email_alert_for_LexPro_closed_won_opps | after, C&U | 1100 | |
| Direct_Debit_and_Credit_Card_Notification_to_Finance_Updated | after, U | 1200 | |
| Opportunity (label: Opportunity_AfterUpdate_MasterFlow) | after, C&U | 1300 | has per-user bypass decision **and fault-notification emails** — org's most modern pattern |

(30 more Opportunity flows exist but are inactive — list in audit folder.)

**Apex triggers — active (9):** SBQQ.OpportunityBefore / SBQQ.OpportunityAfter (CPQ core, heavy),
sbaa.OpportunityBefore (Advanced Approvals), DOZISF.OpsosOpportunityTrigger (ZoomInfo),
trumpet.OpportunityTR, RHX_Opportunity (Rollup Helper — rollups on after events),
local OpportunityTrigger (→ OpportunityTriggerHandler + OpportunityAnalyticsCreate),
local Ast_OpportunityTrigger (CMDT-gated → OpportunityBillingEntityHandler, before),
local OpportunityTriggerMBLChangeEvent (→ OpportunityHandler.LockOppRecords + change publisher).

**Workflow rules:** 1 ("Push Counter"). **Process Builders on Opportunity: none** (6 active PBs org-wide, all other objects).

**Order-of-execution note:** before-save flows → before triggers → VRs → after triggers → after-save
flows (TriggerOrder 1100→1200→1300, then unordered incl. Customer_Journey). Same-record updates inside
CJ (`Update_Records_3`, `Update_customer_journey_run_field`, `CS_Contact_assigned`,
`Create_handshake_BG_Renewal`'s `assignRecordIdToReference` on $Record) re-run the entire stack recursively.

### 1.8 Design question — stage reversion & blanket un-primary: cause or incidental? Correct CPQ procedure?

**For the reference record: incidental to the fault, but structurally dangerous; for NB/Upsell opps: a
direct re-entry trigger.** The stage reversion to "Identify" makes any NB/Upsell opp with
`Customer_Journey_run__c=false` match `NB_just_created` → handshake create + recursive same-record update
inside an already huge transaction. On this Renewal opp neither write matched a branch, yet the
transaction still died — proving the deeper problem is **transaction stacking against a hair-trigger,
heavyweight flow**, not one bad field value.

**Is this the correct CPQ procedure?** The sequence-concept (de-primary → change currency → build new
quote) matches CPQ constraints: primary quote currency must match opportunity currency, and CPQ blocks
currency changes on quotes that have lines — so you can't convert in place; you un-primary and re-quote.
But the v6 implementation is wrong on four counts:
1. **No commit boundaries** — all steps in one transaction is precisely what CPQ docs/practice avoid;
   each step must be its own transaction (screens between).
2. **Blanket un-primary** of all quotes instead of the primary only (multiplies CPQ trigger work; destroys
   the audit trail of which quote was primary).
3. **Stage reversion is not a CPQ requirement** — it's an org business choice and shouldn't share a
   transaction with the currency write. Recommend dropping it from v7 (or, if business insists, doing it
   as the final, separate, fault-handled step after the currency commit).
4. OLI handling is inconsistent (silent mass delete on the no-quote path; on the quote path, synced OLIs
   are left for CPQ to deal with mid-transaction).

**Recommended procedure:** de-flag primary quote → *(commit)* → change currency → *(commit)* → user
creates new quote; stage untouched (or optional separate final step). Exactly the sequence proposed in
the task brief.

Sources: [Change the Currency in a Salesforce Opportunity](https://help.salesforce.com/s/articleView?id=000386724&language=en_US&type=1),
[CPQ error "Changing currency on quotes with line items…"](https://help.salesforce.com/s/articleView?id=000383693&language=en_US&type=1),
[Guidelines for Using Salesforce CPQ in Multicurrency Orgs](https://help.salesforce.com/s/articleView?id=sales.cpq_multicurrency_cpq.htm&language=en_US&type=5),
[Multi-Currency in Salesforce CPQ](https://help.salesforce.com/s/articleView?id=000383453&language=en_US&type=1)

---

## Phase 2 — Target architecture (for approval before any build)

### 2a. Customer Journey hardening (V23 — rebuild in place, not a migration)

Since it's already a record-triggered flow, the work is hardening, with decision parity:

1. **Tight entry conditions.** Add to the start element:
   `ISNEW() OR ISCHANGED(StageName) OR ISCHANGED(Cancelled__c) OR ISCHANGED(Type) OR ISCHANGED(Opportunity_Type_Forecast__c)`
   (formula entry condition), keeping the existing LexPro/ContentSub filter. Every `Opp_Stage` branch
   depends only on these fields + dedupe flags → full decision parity, but currency-only (and any other
   irrelevant) updates no longer enter at all. *Accepted behavioral change to sign off: an opp that
   missed its handshake no longer "self-heals" on a random later edit — only on the next relevant change.*
2. **Move the 5 Group lookups inside the branches that use them** and **log only when a branch actually
   fires** (kills ~14k no-op log rows/week and ~6 SOQL+1 DML per irrelevant save).
3. **Fault connector on every DML element** → shared fault path writing Flow_Log__c with
   `Error_Description__c` = `{!$Flow.FaultMessage}` (via Flow_log_v4 below). Flow_Log__c already has the
   field; nothing populates it today.
4. **Keep the existing bypass** (`Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c`,
   hierarchy custom setting with per-user kill switches — already the org standard; one integration user
   already uses it). No new bypass framework needed; we standardize on this and document it.
5. **Tame recursion:** branch same-record updates (`Update_Records_3` etc.) remain after-save DML (lookup
   stamping can't be before-save when the created record doesn't exist yet), but with entry conditions
   tightened the recursive save no longer re-enters CJ unless a relevant field changed (the recursive
   updates only touch `Customer_Journey__c` / `Customer_Journey_run__c` / `CS_Contact_Added__c` → no
   re-entry). Net effect: ≤1 CJ execution per user save.

### 2b. Currency screen flow v7

```
Screen 0 (implicit start) → log → get opp →
Guard: stage ∈ {Closed Won, Closed Won – Pending Approval, Closed Won - Cancellation, Closed Lost,
                Cancellation - Pending Review, Contract Out} → blocked screen
→ SCREEN 1: current currency, radio choice, same-currency check
→ Step A (own transaction): IF primary quote exists → un-flag THAT quote only
     (update by Id from Get_Primary_quote — not the blanket SBQQ__Opportunity2__c filter)
     fault connector → fault screen ({!$Flow.FaultMessage}) + Flow_log_v4 fault row
→ SCREEN 2 ("Quote de-flagged — click Next to change currency")  ← commit boundary
→ Step B (own transaction): IF un-synced OLIs remain → explicit confirmation screen before deleting
     (never silent); delete → fault-connected
   update Opportunity.CurrencyIsoCode → fault connector → fault screen + log
→ SCREEN 3: success ("create a new quote in <currency>")
```

- **Stage reversion removed** (recommended). If the business confirms it's required, it becomes an
  optional Step C after Screen 3's transaction, fault-handled, never sharing a transaction with currency.
- Each transaction now carries one primary DML + the automation stack — no stacking, no CJ re-entry
  (post-V23 it won't even enter), governor headroom restored.
- Flow remains `SystemModeWithoutSharing` (unchanged from v6) so non-admin sales users can run it.

### 2c. Reusable fault pattern — Flow_log_v4

New autolaunched subflow (v3 untouched for the ~dozen existing callers; migrate opportunistically):
- Inputs: `recordId`, `var_flowname`, `var_recordname` (as v3) **+ `var_errormessage` (text, optional),
  `var_element` (text, optional)**.
- Writes `Flow_Log__c` incl. `Error_Description__c`, `Class_Name__c` (element name), `Record_Id__c`,
  `Triggering_Object__c` (today all unpopulated).
- Convention: call once on fault from any flow's fault connector; success-path logging only where a flow
  actually did work. The master flow's existing fault-email action can be folded in later (out of scope).
- Optional follow-up (flag for backlog, not this task): Flow_Log__c retention job — 14k rows/week needs a purge.

### 2d. Migration / rollout plan

| Step | Action | Rollback |
|---|---|---|
| 0 | KJDEV: reproduce prod fault (Renewal opp + primary GBP quote + 2 synced OLIs, GBP→USD via v6) — debug log pins exact faulting element/limit; validates test bed | n/a |
| 1 | KJDEV: build Flow_log_v4 → CJ V23 → currency v7; run regression suite; **demo to you** | n/a |
| 2 | PROD deploy (after sign-off): Flow_log_v4 first, then CJ V23, then currency v7. **Org deploys flows as Draft** — activate via FlowDefinition in this order; old versions auto-obsolete | Re-activate CJ V22 / currency v6 (versions retained); Flow_log_v4 is additive |
| 3 | Post-deploy: re-run the GBP→USD change on 006Tm00000DBVgwIAH (or sandbox-verified clone scenario) with the business user | — |

**Regression suite (KJDEV, all must pass):** currency happy path (primary quote), no-primary-quote path
(with + without OLIs, incl. the delete-confirmation), same-currency path, closed-stage guard incl. the
two newly added stages, fault path renders + logs (force a fault via temp VR), CJ parity: every `Opp_Stage`
branch (NB Closed Won, Renewal Closed Lost ±budget date, Renewal CW before budget date, Cancelled, NB just
created incl. handshake + lookup stamping, Renewal CW BG, Upsell CW, Contract Out), CJ non-entry on
currency-only change, scheduled-path parity (Newly created Renewal), bypass on/off (custom setting),
recursion: one CJ execution per save (verified via debug log).

### 2e. Addendum — upgrades that take v7 from "solid fix" to world-class

**Tier 1 — fold into the v7 build (cheap, high value):**
1. **Pre-flight validation screen** before any DML: (a) active PricebookEntries exist in the target
   currency for every product on the opp (else the currency DML hard-fails mid-sequence — verified USD
   entries exist for the reference product, but other products may lack them); (b) no pending approval
   (`ProcessInstance` Status='Pending' for the record → block); (c) re-confirm stage guard. Then a
   **preview/confirm screen**: from→to currency, the quote that will be de-flagged, OLIs affected.
   Fail fast and explain, never fault mid-way.
2. **Idempotent resume.** With commit boundaries comes a new failure mode: Step A commits (quote
   de-flagged), Step B fails (currency unchanged). v7's design already self-heals — re-running finds no
   primary quote and proceeds straight to the currency step — but make this an explicit, tested property,
   and have the fault screen state the exact record state plus "run the action again to continue".
3. **Permission gate.** The flow runs `SystemModeWithoutSharing`; anyone who can launch it can flip
   currency on any opp. Gate with a custom permission (`$Permission` check at start), reusing the
   pattern established in the Contact Role rebuild.
4. **Re-validate at each transaction boundary** — re-query the opp after each screen; another user or
   automation may have changed stage/currency between commits.
5. **Audit + notification:** success log row records from→to and the de-flagged quote Id
   (`CurrencyIsoCode` is already field-history tracked); on fault, notify admins via the master flow's
   existing fault-email pattern and show the Flow_Log reference Id on the user's fault screen.

**Tier 2 — what makes it durable beyond this flow:**
6. **ACM × CPQ divergence (new Phase 1 finding):** the org runs Advanced Currency Management (dated
   rates), which CPQ only partially supports — platform conversions use dated rates while CPQ uses
   static rates, so converted opp Amount/OLI prices and a freshly created quote can legitimately
   disagree. Needs a business-visible note and a dedicated repro comparison test.
7. **Renewal-currency question:** the reference case is a renewal opp; renewal quotes price from the
   (GBP) contract/subscriptions. Changing the opp to USD does not change the contract — the new
   "USD renewal quote" may misprice or fall back to list. Business must confirm currency-change-on-renewal
   is the right operation at all (vs. regenerating the renewal). Repro must include this scenario.
8. **Load-shedding beyond CJ:** the limit-pressure disease (always-on entry, unconditional queries)
   likely affects other active opp flows. CJ V23 is the biggest single win; budget a later pass over the
   remaining 11. The permanent guarantee against limit faults is lower baseline load per save.
9. **Observability:** FlowTests for CJ V23 decision branches (regression safety for future editors);
   a scheduled fault-report/dashboard on Flow_Log; a Flow_Log purge job (14k rows/week today).

**Tier 3 — strategic alternative (recorded, not recommended now):** implement the currency operation as
an Apex invocable service (unit-testable, limit-profiled, compensation logic) behind the same screen
flow UX. Declarative + commit boundaries is the right fit for this org's operating model today; revisit
if the operation grows (e.g., automated re-quoting in the new currency).

### Open items needing your decision (with the architecture approval)

1. **Stage reversion to "Identify": drop entirely (recommended) or keep as separate final step?**
2. CJ entry-condition behavioral change (no more "self-heal on any edit") — acceptable?
3. The no-quote path's OLI delete: keep with confirmation screen, or remove OLI deletion entirely?
4. Tier 1 addendum items (pre-flight checks, permission gate, idempotent resume, audit/notification) — include in the v7 build? (Recommended: yes, all five.)
5. ~~Renewal opps: should currency change be allowed on Renewal record types at all?~~
   **RESOLVED 2026-06-12 (KJ): yes — rare but legitimate. Keep renewals supported.** Consequences:
   the regression suite must include the renewal scenario end-to-end (de-flag → currency → new renewal
   quote) and document how the new quote prices against the GBP contract under ACM; the v7 preview
   screen shows a renewal-specific notice ("renewal quotes price from the contract — verify pricing
   after re-quoting") instead of blocking.
