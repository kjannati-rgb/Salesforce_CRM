# Phase A Findings — PFC Triage Cockpit Discovery

**Date:** 2026-07-14 · **Author:** Claude Code session (read-only prod discovery)
**Orgs verified:** PROD `kamyar.jannati@lbresearch.com` / `00D6g0000081IOgEAM` (instance `lawbusinessresearch.my.salesforce.com`; note: the CLI alias is `PROD`, not `lawbusinessresearch` as the brief assumed). KJDEV `kamyar.jannati@lbresearch.com.kjdev` / `00DAe00000D35gVMAR`.
**Zero writes performed against production.** All metadata retrieved to `pfc-triage-cockpit/prod-retrieve/` (not merged into `force-app/`).

---

## 0. Headline: three of the brief's eight ground truths need revision

| # | Brief said | Reality found |
|---|-----------|---------------|
| 1/2 | Clay routing "broken write-back + incomplete coverage" | **There is no Clay return leg in Salesforce at all — and no evidence Clay has ever written to the org.** No Clay integration user exists. `Clay_Routed__c` is set to `false` by the orchestrator and is **editable on both classic layouts and the Scored_Leads page** — the 1,560 `true` records (180d) were ticked **by humans**. The "1 successful rep write" was Sam Tucker manually editing a record. Fit Score fill: 0 of 13,444 records in 365 days. |
| 3 | "Workflow fields dead; every record at stage New" | **Wrong on stages.** 180-day stage spread: New 1,652 / Working 1,738 / Nurturing 220 / Converted 308 / Disqualified 2,428 — reps *do* progress records (65% are past New). What's dead is *structured* working data: `Next_Step__c` 1.5%, `Next_Contact_Date__c` 2.6%, `Comments__c` 6.9%. `Reason_Disqualified__c` is 42% (≈94% of Disqualified). |
| A1a | Date_Completed automation "claimed but may be missing" | **It exists and works**: two active classic Workflow Rules (`Completed Date on Forms`, `Remove Completed Date on Form`). Zero unstamped Converted/Disqualified records in 180 days. Phase B4 = *migrate to flow during this project* (Workflow Rules are EOL), not build-from-scratch. |

Also: dedupe linking (brief Finding 4/5) is **already live** — see §2b.

---

## 1. A1 — Flow forensics (answers a–d)

Active suite confirmed as in the brief (plus discoveries). Retrieved and read all 11 flows + workflow file.

**a. Where is `Date_Completed__c` stamped?**
Classic Workflow Rules on the object, both ACTIVE and healthy:
- `Completed Date on Forms`: stage = Converted OR Disqualified → field update `NOW()` (`onCreateOrTriggeringUpdate`).
- `Remove Completed Date on Form`: stage ≠ both → nulls the field.
Data check: 0 Converted/Disqualified records missing the stamp (180d). **B4 changes from "build" to "migrate WFR → PFC_Stamp_Work_Fields before-save"** (one behavioural nuance to preserve or consciously drop: the *removal* rule un-stamps on reopen, so the current behaviour is "date of latest close", not point-in-time-first-close).

**b. Why was `PFC_Check_And_Link` deactivated?**
Deliberate supersession, not failure. `PFC_On_Save` (status Active, description: "REV-57/REV-77: single consolidated PFC after-save flow… Replaces On_Pardot_Form_Creation + PFC_Check_And_Link + PFC_Add_Campaign_Member") absorbed its logic: same person + brand-grain matching (`Product_Brand__c` with `Brand__c` legacy fallback, skip blank/"Other"), most-recent-*open* match → `Related_Form_Completion__c`. `PFC_Check_And_Link` is marked Obsolete; `PFC_Add_Campaign_Member` likewise. **Linking is live and working: 209 records have `Related_Form_Completion__c` set (all post-cutover; June–July run-rate ≈ 9% of new records).**
→ **B3 is largely done.** Remaining deltas vs the brief's spec: brief wanted match on Email OR Prospect_ID within 90 days and *earliest* open match; live logic matches on the Lead/Contact lookup + same brand, *latest* open match, no time window. Decide whether to extend, not rebuild.

**c. Where is `Sales_Rep__c` set — where's the Saurabh hardcode?**
**There is no hardcode.** Both the live orchestrator and the legacy `Create_Pardot_Form_from_Task` set `Sales_Rep__c = $Record.OwnerId` *of the triggering Task*. Pardot creates those Tasks via the **B2BMA Integration** user and they land owned by **Saurabh Patil** (`0054L000003kLUGQA2`, sysadmin — presumably the connector's default assignee). PFC Owner follows the same path (fresh records: `Owner = B2BMA Integration` until a rep claims it). So the fix point for B1 is: **stop inheriting Task.OwnerId; assign the queue explicitly in the orchestrator's Create element** (and check the Pardot connector's task-assignee setting).
Reassignment reality: only 24 `Sales_Rep__c` history changes in 90 days org-wide (20 = one manual batch by Akhat Mussabayev, Custom: Sales Profile, triaging "Scored Lead" records on 2026-07-10). Records effectively never leave Saurabh.

**d. Does anything write `PFC_Source__c`?**
Yes — the orchestrator, from `PFC_Task_Mapping__mdt.Source__c`, **since the REV-57 cutover (first populated records: June 2026;** 623 in June, 526 July-to-date; 1,150 total = 8.7% of 365d records). The 88% null = pre-cutover records. Backfill (E3) can therefore reuse the same CMDT mapping rules against Task subjects / Form_Name.

**REV-57 cross-reference (brief asked):** REV-57 is not "planned" — it has shipped. Orchestrator + PFC_On_Save + Relink + Log_Fault + CMDT mappings are live; legacy creator flows deactivated. No collision risk for Phase B as long as changes are made *to* this suite rather than alongside it.

**Flow health:** `Flow_Log__c`, 90 days: zero fault rows from the REV-57 suite. 454 rows from `Pardot Form completion Create task based on Next Contact date` — but that legacy flow logs **every execution** unconditionally via `Flow_log_v3` (noise pattern worth cleaning in Phase B; it's also the only remaining pre-REV-57 active flow, still gated on `Disable_Process_Builders__c` rather than the flow kill switch).

## 2. A2 — Clay round-trip forensics

**a. Who stamps `Clay_Routed__c`?** Nobody legitimate. Field default `false`; orchestrator explicitly writes `false`; no flow/trigger/workflow/quick-action writes `true`; no history tracking on the field. The field sits **editable** on both classic layouts ("Pardot Form Completion Layout", "Scored Leads Layout") and on the orphaned Scored_Leads flexipage (read-only on Record_Pagev2). Every one of the 1,560 `true` records (180d) was last modified by a human (top: Kamyar 350, Sergio Otero Felipe 177, Matt Oginsky 154 …); zero remain untouched-since-create. Distribution across all stages incl. 366 still-New. **Conclusion: reps (and admins) tick it manually — as attribution bookkeeping, not routing.** The help text ("Automatically populated. Do not edit manually") describes an integration that was never connected.

**b. Return-leg mechanics.** No Clay-named user, no integration writes on the object (only creator in 180d: B2BMA Integration 6,344 of 6,346). `Fit_Score__c` / `Score_Reasoning__c` / UTM fields: **0 populated in 365 days** — nothing has ever landed. The "one successful rep write" from the brief dissolves under history: record `a5EPx00000X12OFMAZ` was created by B2BMA and hand-edited by Sam Tucker. **The Clay→Salesforce leg (auth, user, field mapping) has never been built.** FLS analysis is moot until an integration user exists.

**c. Coverage rule.** There is none on the Salesforce side — no dispatch element, no allowlist, no callout. If Clay reads prospects at all, it does so entirely outside the org (Pardot-side or CSV), invisible from here. The "78% never entered the Clay path" framing should be retired: the flag measures *manual ticking habits*, not dispatch. Flag=true concentrates in RT Form Completion (1,554/6,130) + Scored Leads (6/74); Events Sponsorship & Newsfeed all false.

**d. Fixes and owners.**
- *Clay side (owner: whoever holds the workbook — open question #1):* build the entire return leg — dedicated Salesforce integration user + writes of `Sales_Rep__c`, `Fit_Score__c`, `Score_Reasoning__c`, `Clay_Routed__c` (as response stamp). This is greenfield, not repair.
- *Salesforce side (this project):* B1 queue default in the orchestrator; FLS for the future integration user's permission set; **make `Clay_Routed__c` read-only on layouts/pages** once Clay actually writes it (its data as ticked today is meaningless for the "Clay routed" semantics — recommend renaming or resetting; the LWC should not display today's values as if they meant routing).
- The brief's `Sent_to_Clay__c` dispatch/response split is still sound *if* dispatch ever becomes Salesforce-initiated; today there is nothing to split.

## 3. A3 — Page assignment audit

- **Org default record page (desktop + mobile): `Pardot_Form_Completion_Record_Pagev2`** (View action override on the CustomObject). This is the page to supersede in Phase C; keep as rollback per C7.
- **`Scored_Leads` flexipage + "Scored Leads Layout": orphaned.** Not referenced by any of the 10 retrieved apps (LightningSales, Sales, Lead_Generation, Sales_Operations, LightningSalesConsole, Sales_Reach, Marketing, REVGRD, Sales_Leadership, OnlineSales) and no app/record-type override found. Someone already attempted a triage-page variant (it even displays Fit fields + Clay_Routed) and never wired it up. Confirm in Setup UI, then treat as dead metadata to retire or cannibalise.
- **Six record types** (brief assumed fewer): Form_Completion (default flow output), Scored_Leads, Events_Sponsorship, Marketing_Services, Newsfeed_Subscribers, Master. The cockpit's Dynamic Forms visibility rules must account for RT, at minimum RT-specific tabs/sections for Events_Sponsorship and Newsfeed_Subscribers (only 3 Newsfeed records created in 180d though — check whether that RT is really in use before investing).
- 4 validation rules on the object, incl. `Sales_People_Cant_Change_Stage_to_Conve…` and `Disqualified_Reason_Mandatory` (explains healthy 94% Reason_Disqualified fill on Disqualified) — the C5 Disqualify screen flow must satisfy these, not bypass them.
- ~150 list views on the object, heavily personal ("Nina Open Forms", "Copy of…") — E1 should include a cull proposal.
- 3 quick actions exist: `Convert_Lead` (screen flow `Pardot_Lead_Conversion`, active), `Create_Opportunity` (Create action — answers part of C5's "Convert to Opp" question: something already exists), `NavigateToRecord`.

## 4. A4 — Field usage (365 days, 13,444 records)

Full CSV: `pfc-triage-cockpit/pfc-field-usage-365d.csv`. Lowlights driving layout decisions:

| Band | Fields |
|---|---|
| **0.0%** | all 5 UTM fields, `Fit_Score__c`, `Score_Reasoning__c`, `Account_Lead__c`, `Lexology_Newsfeed_Subscriber_Date__c` |
| **<3%** | `Next_Step__c` 1.5%, `Related_Form_Completion__c` 1.6% (all post-June), `Next_Contact_Date__c` 2.6%, `Work_Jurisdictions__c` 2.2% |
| **3–11%** | `Work_Areas__c` 3.0%, Opp fields ≈5.4%, `Comments__c` 6.9%, `PFC_Source__c` 8.7%, `Product_Brand__c` 10.9% |
| **38–46%** | `Campaign__c` 38%, `Reason_Disqualified__c` 42%, Contact link ≈46% |

Notes: the UTM section planned for the Attribution tab (C4) currently has literally nothing to show — its `≠ null` visibility rule is correct and will simply keep it hidden until Pardot starts sending UTM values (separate pipe question). `Account_Lead__c` at 0% is a retire candidate. Funnel counters (`Identify__c`…) populated but reporting-only, as assumed.

## 5. Corrected success-criteria baselines (§9 of the brief)

| Metric | Brief baseline | Actual (measured) |
|---|---|---|
| New PFCs to real rep/queue | ~0% | correct (~0.04% off-Saurabh among flagged; 24 reassignments/90d) |
| Fit Score on Clay-routed | 0% | correct (0 in 365d) |
| Duplicates auto-linked | 0% | **≈9% of new records already linking (live since June)** — baseline needs re-anchoring on match-rate quality, not existence |
| Progressed past New in 5 days | ~0% | **65% eventually progress (timing not yet measured)** — recompute with CreatedDate vs first stage-change from history before committing to the 60% target |
| Next_Step on Working | 0% | 1.5% overall |

## 6. Revised open questions for humans (supersedes brief §10)

1. **Does a Clay→Salesforce write-back exist anywhere (even half-built)?** Per the REV-57 decision record (June 2026), **Ashton operates Clay** and "Clay owns both OwnerId and Sales_Rep__c assignment" — but org evidence says it has never written. If Clay is only a concept so far, Phase B's "repair the return leg" becomes "specify and build it", and the SLA sweep becomes the *primary* routing safety net rather than a fallback.
2. What do reps *think* `Clay_Routed__c` means? 1,560 manual ticks in 180 days is a habit; renaming/repurposing the field will break their workflow unless communicated. Reset the historical values or preserve as `Legacy_Clay_Flag`?
3. The `Scored_Leads` flexipage/layout/record-type cluster — abandoned experiment to retire, or requirement input for this cockpit? (It contains the same ideas: fit fields on page, scored-lead record type.)
4. Confirm the Pardot connector Task-assignee setting (why Saurabh owns the tasks) — changing that default is a one-click alternative lever for B1's queue default.
5. Brief Qs 2–4, 6 unchanged (CSM routing for existing customers, SLA threshold + alert recipient, Convert-to-Opp UX — noting `Create_Opportunity` quick action already exists, score bands).
6. UTM fields have never been populated — is a Pardot-side change queued to send them, or should the Attribution tab drop them?

## 7. Artefacts produced

- `pfc-triage-cockpit/prod-retrieve/` — full prod metadata (11 flows, workflow rules, object + 62 fields, 2 layouts, 2 flexipages, 6 RTs, 4 VRs, ~150 list views, 10 apps)
- `pfc-triage-cockpit/pfc-field-usage-365d.csv` — per-field population stats (A4 deliverable)
- `pfc-triage-cockpit/pfc-records-365d.csv` — raw 365d export backing the stats (13,444 rows; contains prospect PII — do not circulate; delete after Phase B baselining)
- `pfc-triage-cockpit/salesrep-history-90d.csv` — Sales_Rep__c audit trail extract
- `pfc-triage-cockpit/BUILD-LOG.md` — session log

**Gate A status: COMPLETE — awaiting human review before Phase B.**
