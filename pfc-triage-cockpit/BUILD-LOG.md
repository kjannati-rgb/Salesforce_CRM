# BUILD-LOG — PFC Triage Cockpit

> Running log per session protocol. Newest entries at the bottom. Rollback notes inline.

## 2026-07-14 — Phase A discovery (read-only)

- **Org identity verified** before any operation: PROD = `kamyar.jannati@lbresearch.com` / `00D6g0000081IOgEAM` (CLI alias `PROD` — the brief's `lawbusinessresearch` alias does not exist in this CLI setup); KJDEV = `kamyar.jannati@lbresearch.com.kjdev` / `00DAe00000D35gVMAR`.
- **No writes to any org.** No deploys. Working tree `force-app/` untouched — all retrievals went to the isolated `pfc-triage-cockpit/prod-retrieve/` output dir.
- Retrieved from PROD: PFC flow suite (8 named + `Pardot_Lead_Conversion` + 3 legacy inactive), `Workflow:Pardot_Form_Completion__c`, `CustomObject:Pardot_Form_Completion__c`, both Layouts, both FlexiPages, 10 CustomApplications.
- SOQL forensics (all read-only): Clay flag/rep/stage aggregates, `Pardot_Form_Completion__History` extracts (Sales_Rep 90d), user identification, Flow_Log health, 365-day full-field export (13,444 rows).
- Deliverables: `PHASE-A-FINDINGS.md`, `pfc-field-usage-365d.csv`, `salesrep-history-90d.csv`, `pfc-records-365d.csv` (PII — local only).
- **Gate A: reached. Halted for human review before Phase B.**
- Data-hygiene note: `pfc-records-365d.csv` contains prospect PII (emails/phones); keep out of git and delete after Phase B baselining.

## 2026-07-14/15 — Phase B build (KJDEV only, zero prod writes)

Gate A approved by Kamyar in-session; decisions: B3 flow matching unchanged (LWC matches wider in Phase D), Clay_Routed__c locked read-only now, SLA = 4 working hours.

**Deployed to KJDEV** (21 components, `sf project deploy start --source-dir pfc-triage-cockpit/kjdev-build`, all-or-nothing, Succeeded 2026-07-15):
- `PFC_Triage_Queue` (Queue for Pardot_Form_Completion__c)
- `Routing_Overdue__c` checkbox on PFC
- `PFC_Settings__mdt` (+ fields Routing_SLA_Hours=4, Alert_Chatter_Group='CRM Support', Sweep_Disabled) + `Default` record
- Apex: `PFCRoutingSlaService` (+85% cov; uncovered = CMDT-kill-switch/queue-missing guards, not DI-able), `PFCRoutingSlaSweepSchedulable` (100%), `PFCRoutingSlaServiceTest` (7/7 pass incl. bulk-200, idempotency, chatter, missing-group)
- Flow `Pardot_Create_PFC_Orchestrator` v5 Active: creates PFC owned by PFC_Triage_Queue, Sales_Rep__c no longer inherited from Task.OwnerId (kills the Saurabh default)
- Flow `PFC_Stamp_Work_Fields` v2 Active: + Date_Completed stamp-once on Converted/Disqualified (B4, replaces WFRs; un-stamp-on-reopen behaviour DROPPED deliberately), + clears Routing_Overdue when a User owns the record
- Workflow rules `Completed Date on Forms` / `Remove Completed Date on Form` deactivated
- Both classic layouts: Clay_Routed__c flipped Edit→Readonly
- Permsets: `PFC_Clay_Integration` (integration user, unassigned; needed allowDelete for Modify All), `PFC_Triage_Cockpit_Fields` (rep read-only FLS; assigned to Kamyar in KJDEV)

**Verification (Gate B):**
- Single-record smoke PASS: Task → PFC queue-owned/rep-blank/source stamped; DQ → Date_Completed stamped; reopen → stamp survives; re-close → not overwritten; flag+simulated-Clay-response round trip → rep/score/reasoning/Clay_Routed land, Routing_Overdue clears on user ownership.
- Bulk 200 Tasks → 200 PFCs queue-owned, no governor errors.
- Sweep E2E (CMDT temporarily 0h, restored to 4h): 3/3 flagged + Chatter digest with links posted to 'CRM Support' group (created in KJDEV: 0F9Ae00000076BxKAI). This is also the "withheld Clay response" scenario.
- Flow_Log__c: 0 PFC faults.
- Hourly schedulable job active in KJDEV: 'PFC Routing SLA Sweep' (08eAe00000O36BA, cron 0 0 * * * ?).

**Gotchas hit:** permset description >255 → shortened; ModifyAll needs allowDelete; MDAPI field invisible to anon-Apex SOQL until permset FLS assigned; Kamyar's user-level Application_Settings__c row in KJDEV disables autolaunched flows (temporarily set false for tests, RESTORED to true after).

**Rollback (KJDEV):** deactivate orchestrator v5 / stamp v2 via FlowDefinition (prior versions Obsolete but redeployable), re-activate the 2 WFRs, abort scheduled job, delete queue/field/CMDT/permsets. Prod untouched.

**Prod deployment: NOT done — Phase F.**

## 2026-07-15 — Phase C build (KJDEV only)

Mockup file unavailable (not on this machine) — built from the brief's C2–C6 spec per Kamyar's instruction; Gate C walkthrough is the correction point.

**Deployed to KJDEV:**
- FlexiPage `PFC_Triage_Cockpit_Record_Page` — Dynamic Forms; header highlights with page-level Dynamic Actions (Disqualify [hidden when closed], Convert_Lead [lead-linked, not converted], Create_Opportunity [contact-linked, not converted], Route_to_Account_Owner [contact-linked]); Path; "Key Details" section with Contact/Lead conditional variants (Account+Account Owner vs Company+Sales Rep); Triage/Attribution/Outcome tabs with visibility rules (UTM section: UTM_Source ≠ null; newsfeed date: PFC_Source = Newsfeed; Reason DQ: stage = Disqualified; opp metrics: Converted_to_Opportunity = true — lookup fields don't support NE in visibility rules); funnel counters + ID fields + raw Fit fields omitted; sidebar = Opportunity related record (Converted only) + Activity panel + Linked Form Completions list.
- **Activated as org default** (View overrides Large+Small on CustomObject; v2 kept as rollback). NOTE: deploy only the bare object-meta.xml — bundling record types trips a pre-existing `Reason_Disqualified__c` picklist encoding mismatch ("Duplicate Scored Lead" + non-breaking space).
- PathAssistant `Pardot_Form_Completion_PFC` (Form_Completion RT): guidance copy all 5 stages (drafted, review at Gate C), key fields Working → Next_Step + Next_Contact_Date, Nurturing → Next_Contact_Date, Disqualified → Reason_Disqualified.
- Screen flows (Active): `PFC_Disqualify` (required reason via picklist choice set + optional comment prepended to Comments; update + fault screen), `PFC_Route_to_Account_Owner` (confirm screen w/ owner name + optional note → Chatter @mention on record + review Task due +2 days).
- Quick actions: `Pardot_Form_Completion__c.Disqualify`, `Pardot_Form_Completion__c.Route_to_Account_Owner`.

**Deviations from brief (platform limits, review at Gate C):**
1. Update-type quick actions CANNOT be created via Metadata OR Tooling API (persistent gack, err 1450044978; existing ones were UI-created) → sidebar Related Record components for Lead/Contact dropped (Lead has no Update action to borrow). Key Details links + Phase D quality card cover the context; can be added manually in App Builder if wanted.
2. "Log Outreach" quick action dropped: object-scoped LogACall metadata rejected (TargetField), global LogACall not referenceable in object dynamic actions → the sidebar Activity composer's native Log a Call covers it.
3. "Account Owner" in highlights = cross-object fieldItem `Account_Contact__r.OwnerId` (read-only display).
4. Toast on Disqualify finish not possible declaratively — flow closes modal on finish instead.

**Gate C test records (KJDEV):** GATEC-1 lead-linked/overdue (a5EAe00000GHccMMAT), GATEC-2 contact-linked (…NMAT), GATEC-3 UTM (…OMAT), GATEC-4 newsfeed (…PMAT), GATEC-5 disqualified (…QMAT), GATEC-6 opp-linked (…RMAT) + Gate C Test Firm LLP / Cara ContactTest / Larry LeadTest / Gate C Test Opp. Insert-time checks passed: On_Save renaming, Account_Contact stamping, Date_Completed stamped on both closed records at create.

**Page assignment gotcha (KEY for Phase F):** org-default View override is NOT enough — v2 was ALSO assigned via `profileActionOverrides` in **`standard__LightningSales`** (88 blocks: Form_Completion + Newsfeed + Scored_Leads RTs × profiles × form factors), `standard__LightningSalesConsole` (6 profile-level blocks), ALM + MBL_Seminars (Newsfeed). App+RT+profile assignments beat org default, so the old page kept rendering. Patched Form_Completion-RT and RT-less blocks → cockpit in both standard apps (64+6 blocks); **Newsfeed/Scored_Leads RT assignments left on v2 deliberately**; ALM/MBL untouched. NOTE: Phase A's prod audit missed this — it retrieved custom app `LightningSales`, not `standard__LightningSales`; prod almost certainly has the same standard-app assignments and Phase F must patch them too.

**Runtime walkthrough (browser, KJDEV):** cockpit page renders as org default; action variants verified — lead-linked: Disqualify+Convert Lead; contact-linked: Disqualify+Create Opportunity+Route to Account Owner; disqualified: Disqualify hidden (Convert Lead still visible = v2-parity rule, Gate C question); UTM Tracking section visible on UTM record, hidden otherwise; Key Details/Working the Form/Prospect Detail/Attribution sections render. Screen flows PFC_Disqualify + PFC_Route_to_Account_Owner Active. Pixel screenshots not captured (browser-pane screenshots time out on Lightning; structural verification via accessibility tree/JS instead) — formal screenshot set to be taken during Kamyar's Gate C walkthrough.

**UAT note:** Kamyar's user-level Application_Settings__c row disables autolaunched flows — flip `Disable_Autolaunch_Lightning_Flow__c` to false on row a3W4L000001UsZHUA0 before UAT-clicking Disqualify/stage changes, or the B4 stamp won't fire for him (restored to true at end of this session).

## 2026-07-15 (later) — Mockup reconciliation

`pfc-record-page-mockup.html` provided after the build (archived into this folder). Structured diff done; page matched the mockup on highlights fields/variants, action switching, tab structure, visibility rules, and Disqualify semantics. Three gaps fixed and deployed to KJDEV:
1. Path New stage: added key fields Next_Step__c + Next_Contact_Date__c and aligned guidance copy (quality-card-first, 4-working-hour SLA kept over the mockup's "1 business day" since it reflects the built B1 sweep).
2. Sales_Rep__c added to Triage "Working the Form" (mockup shows it in both highlights and triage — duplicate field placement DOES deploy fine on Dynamic Forms; earlier avoidance was unnecessary).
3. Product_Brand__c added to Attribution alongside legacy Brand__c.

## 2026-07-15 (later) — Phase D: pfcQualityCard (KJDEV)

**Deployed (39 components):**
- `PFCQualityCardController` (+test, 96% coverage, 7/7 pass) — `getCardData(recordId)` cacheable wrapper: mode (lead/contact on Contact__c), fit score/reasoning, domain classification, duplicates, firm rollup. `with sharing`; subscription aggregate alone runs in an inner `without sharing` class (reps lack CPQ sharing; aggregate counts only — ATM precedent).
- **Duplicate matching redesigned**: Email__c/Prospect_ID__c are cross-object formulas (NOT filterable in SOQL) → matcher resolves Leads+Contacts by email then finds sibling PFCs via Lead__c/Contact__c lookups (also catches same person as lead AND contact). 90 days, cap 10, display-only (flow linking unchanged per Phase B decision).
- **Firm rollup** mirrors FirmSalesSummaryController's active definition: `Ultimate_Parent__c = firm, StartDate <= today <= EndDate, TerminatedDate = null, Bundled = false`, grouped by Product2.Family.
- New CMDTs + seeds: `Freemail_Domain__mdt` (19 domains), `Brand_Family_Map__mdt` (10 rows: Lexology→Subs - Lexology Pro; GAR/GCR/GIR/GRR/GDR/GBRR/IAM/WTR/Latin Lawyer→Subs - Specialist Platforms; "Other" unmapped deliberately). **Mapping is best-guess config — review rows before prod.**
- `pfcQualityCard` LWC: mockup-faithful dual mode (gauge w/ provisional bands ≥70 green / 40–69 amber / <40 red — Clay owner to confirm, brief Q6; "Score pending — Clay enrichment runs within ~10 min" empty state; freemail/corporate/Clay/source badges; inline duplicate list with record links; Account Context big number + holdings summary + red entitlement flag with mockup copy; no-subs empty state). Jest 4/4 (both modes + both empty states). Placed on the cockpit page between Key Details and tabs.

**Test-org gotchas hit (all in the test class now):** Ultimate_Account__c lookup filter requires RT "Firm"; Product2.Reporting_Stream__c is org-required AND restricted-dependent on Division__c (validFor bitmap helper resolves a valid pair — dependency IS enforced on DML for restricted picklists); "Subscription Process - Edit" PB breaks on contract-less subs → reuse `FirmRollupTestData.bypassOrgAutomation()` (test-only class — anonymous-apex scripts must inline the Application_Settings upsert instead).

**Gate D runtime evidence (browser, KJDEV):** GATEC-1 lead mode: gauge 83 + corporate badge + Clay/source badges + "2 other completions" dupe warning (Larry's real siblings). GATEC-2 contact mode: "Account Context", 6 active subs, holdings by 3 families, existing-customer badge, entitlement flag firing (Lexology vs seeded Subs - Lexology Pro). Seed script `scripts/gated_data.apex` (6 subs + simulated Clay score 83 on GATEC-1). NOT verifiable in empty KJDEV: mega-firm load (<1s target) — check during prod UAT; fallback to FSS persisted rollups documented in the brief if slow.

## 2026-07-15 (later) — Phase E + F

**E1 (deployed to KJDEV):** list views `My_Triage` (Mine, New/Working; Fit Score/Routing Overdue/Next Step columns) and `Team_Triage` (filterScope=Queue on PFC_Triage_Queue). Kanban = per-user display setting (gear → Kanban), not metadata; noted in UAT script. Sorting is also UI state — "sorted Fit Score desc" from the brief is a user click, not deployable.

**E2 (prod, read-only):** funnel-counter consumer inventory → `FUNNEL-COUNTER-INVENTORY.md` + `funnel-counter-report-hits.csv`. Dependency API: 0 consumers all 6 fields (control on Sales_Stage__c = 92, proving method valid for Flow/Layout/VR/FlexiPage; Reports NOT indexed by the API in this org). Report usage from REV-73's cached Analytics describes (4,101 reports run in 12 mo to 2026-07-03): bare tokens over-match (2,596 — Close__c etc. exist on Opportunity); qualified tokens still over-match (131 — describe embeds the report TYPE's full field catalogue); restricting to `reportMetadata` gives the truth: **5 of 6 fields used by ZERO reports; only Closed_Won__c is live (99 reports, all CRT Custom_Pardot_Form_Completions_with_Opps__c, "% won" family, heavy folder-copy sprawl)**. Retirement path documented (Converted_to_Sale__c parity → repoint → retire).

**E3:** `PFC-SOURCE-BACKFILL-PROPOSAL.md` — 61,165 null-source records, bucketed with measured counts (RT-based + form-name patterns; 99.98% classifiable; 49 MQL-pattern in the null-RT bucket, 0 EVT/newsfeed). Proposal only; pairs with REV-76.

**F:** `UAT-SCRIPT.md` (5 scenarios + open decisions), `rev-package.xml` (full manifest; Workflow deploys at ACTIVATION not body — deploying it deactivates the WFRs immediately), `PROD-DEPLOYMENT-RUNBOOK.md` (4 phases, per-step confirmation, backups-as-rollback, RunSpecifiedTests, standard-app profileActionOverrides patch, day-1/7/30 checks). **No production writes performed.**

## 2026-07-16 — FULLUAT deployment (Cayla's UAT environment)

**FULLUAT (00DAd00000CZR4rMAH) was pre-REV-57** (refresh predates the June cutover: legacy creator flows active, no REV-57 fields/CMDTs/permset — yet FirmRollupTestData present from a selective deploy). Deployed the FULL stack as a prod-runbook rehearsal:
1. Baseline staged in `fulluat-stage/`: Lead+Contact newsfeed date fields, PFC_Task_Mapping + PFC_Campaign_Mapping CMDTs + records (force-app), PFC_REV57_Field_Access, ALL PFC fields + 4 VRs + PFC_On_Save + Relink (prod-retrieve) — deployed together with `kjdev-build/` in ONE transaction: **161/161 components**.
2. FULLUAT deploys flows **Active** (unlike prod!) — new flows landed live; swap = deactivating 3 legacy flows (Create_Pardot_Form_from_Task, On_Pardot_Form_Creation, Move_Lead_to_Contact_on_Pardot_Form) via FlowDefinition=0. ⚠ prod runbook still needs the full activation sequence.
3. Page activation: object View overrides + standard__LightningSales (64 blocks) + Console (6) patched v2→cockpit, same as KJDEV.
4. Tests: **15/15 pass in FULLUAT** (both suites; prod-copy org validates Firm RT, Reporting_Stream, Subscription PB quirks).
5. Ops: sweep scheduled hourly (verified next fire), Chatter group "CRM Support" created, permsets assigned to **Cayla Vichot** + Kamyar (+ PFC_Clay_Integration to Kamyar for seeding — MDAPI-fresh fields invisible even to sysadmins, gotcha #7 again), Cayla has NO automation bypass rows ✓.
6. Seed (fulluat_seed.apex): 3 Tasks → orchestrator → queue-owned PFCs (full chain verified live incl. On_Save renaming); Cayla-owned: UTM+score-83 gauge record, contact-linked at **Rouse AB (real firm, 113 active subs)** for Account Context + IAM entitlement check, Disqualified (Date_Completed stamped ✓), Converted vs real won opp (stamped ✓); queue-overdue record for the sweep/list-view demo. Lead inserts need Country (org VR).
7. Verified: 0 PFC Flow_Log faults; overdue flag semantics correct; closed records skipped by On_Save (expected).

**Rollback (FULLUAT):** legacy FlowDefinitions back to previous versions + object/app files from `fulluat-patch/` pre-patch retrieve. Note FULLUAT now runs the REV-57+cockpit world — anything else being UAT'd against PFC there inherits it.

## 2026-07-17 — UAT round 1 feedback (Cayla, via completed UAT-SCRIPT.docx on SharePoint) + fixes

Scenarios 1–3 done: 7 pass, 3 issues. Both real defects FIXED and deployed to FULLUAT + KJDEV:
1. **Quality card "could not load" for Cayla (step 6)** — REV-69 gotcha again: permsets had no Apex classAccesses for `PFCQualityCardController`, so the wire dies for non-admin users (admins unaffected → why my walkthroughs passed). Fixed: classAccesses added to `PFC_Triage_Cockpit_Fields`. LESSON now 3-for-3 across features: every @AuraEnabled controller needs classAccesses in its permset from day one.
2. **"Reminder task did not appear" + her Next Step/Next Contact Date edits silently lost (step 7)** — REAL REGRESSION from B1: the legacy reminder flow sets Task.OwnerId = PFC owner; on queue-owned records Tasks can't be queue-owned → "Queue not associated with this SObject type" → **the flow error rolled back her entire save** (fields lost, no task, unclear error). Fixed: new flow version with `taskOwnerId = IF(owner is user, owner, $User.Id)` in both create elements; verified in FULLUAT (update that previously failed now saves + task created). Flow added to rev-package.xml + runbook step 11b — MUST ship with the queue-default in prod.
3. **Kanban "didn't show me anything" (step 2)** — platform limitation: Kanban does not display queue-owned records, and Team Triage is queue-scoped. Not fixable; Kanban is for My Triage (user-owned) only. UAT docs to be corrected.
Non-issues: step 9 Pardot "Unlinked Account" on opp engagement history = sandbox has no Pardot connector mapping (works in prod); step 12 wording clarified (comment = the optional box inside the Disqualify dialog).
New decision added from her feedback: make Next Step / Next Contact Date REQUIRED at Working? (Success metric targeted 70% fill, not 100% — needs Greg/Kam call; would be a VR scoped to user-owned records.)
Cayla should REFRESH and redo steps 6–7, then continue scenarios 4–5.

## 2026-07-21 — UAT round 2 (Greg, all scenarios, signed 21/7) + fixes deployed to FULLUAT & KJDEV

Triage of Greg's results:
- **Timing artifacts (his scenarios 1–3 ran before his 17-Jul permset assignment):** step 1 missing Fit Score/Routing Overdue/Source columns, step 5 "no Routing Overdue field", step 6 quality card error — all FLS/classAccess visibility; needs re-test only.
- **Real fix 1 — UTM fields had NO permset FLS anywhere** (step 17; old never-used fields, visible to sysadmins only via ancient profile FLS): added all 5 UTM_* (read) to PFC_Triage_Cockpit_Fields.
- **Real fix 2 — Brand_Family_Map corrections (step 16, per Greg via Mahnaz): GDR + GBRR deleted** (products don't exist); Lexology→Subs - Lexology Pro confirmed correct. Destructive deploy both orgs + manifest updated.
- **Enhancement shipped (Greg's ask, step 7): Next_Step__c + Next_Contact_Date__c now history-tracked** (14/20 tracked-field budget) **+ History related list added to the cockpit sidebar** — gives the "is the rep keeping this current" audit trail he wanted.
- **UX fixes shipped:** Key Details section moved ABOVE the Path (step 13 — matches mockup order, ends the "which header?" confusion); Comments__c added to the Disqualified path key fields (step 10).
- **By-design, explained not changed:** step 9 manual stage→Converted blocked by VR (that's the REV-69-era guard working; the step means the Convert Lead BUTTON); step 12 DQ one-way for non-admins = pre-existing lock VR; step 4 Sales Rep field ≠ Owner (Change Owner is the routing action); step 2 Kanban can't show queue-owned records (platform).
- **Open/unexplained:** Greg reports Stina's Attribution tab missing PFC Source + Product Brand while UAT records show them (same session, values populated, he has the permsets) — awaiting his re-test + screenshot.
- **New decision items from round 2:** lock newly-created opps to Identify stage in the convert flow?; rename/clarify Sales Rep vs Owner on the page?; (carried) required Next Step/Next Contact Date at Working.
Re-test asks: Greg steps 1, 5, 6, 17 + Stina attribution; Cayla steps 6–7.

## 2026-07-21 (later) — Routing target changed: Account Owner → Firm Account Team (Kamyar's decision)

Business rule: account owners are NOT the routing target; the **Account Team on the Firm-record-type account** is. Built + deployed to FULLUAT & KJDEV:
- New screen flow **`PFC_Route_to_Account_Team`**: office → `Ultimate_Account__c` → firm; recipient = firm AccountTeamMember matching `PFC_Settings__mdt.Route_Preferred_Roles__c` (CSV priority, seeded "LexPro BDM" — the ONLY role on firm teams today, 3,966 members in FULLUAT), else first team member; **fallback to firm owner ONLY when no team exists, with explicit warning copy**. Chatter @mention + review Task to the recipient. GOTCHA: `TeamMemberRole` is a picklist — flow formulas need `TEXT()` around it or deploy fails "field integrity exception".
- New quick action `Route_to_Account_Team`; flexipage action swapped (same Contact≠null visibility). Old `Route_to_Account_Owner` action DELETED (destructive) + old flow deactivated in both orgs (v-files archived in `pfc-triage-cockpit/retired/`). Deploy ordering matters: flexipage must stop referencing the old action in the SAME constructive deploy, or the destructive delete fails.
- New CMDT field `Route_Preferred_Roles__c` on PFC_Settings + Default record value.
- Manifest updated (new flow/action/CMDT field; old names removed). UAT-SCRIPT.md step updated.
- FULLUAT test data: Cayla seeded as LexPro BDM on Rouse AB firm (ATM 01MAd00000BIThxMAH) → Greg's step-15 retest routes to her.
- **Account Owner field DROPPED from Key Details (Kamyar, 21-Jul)** — contact variant now shows Prospect / Job Title / Account / Country / Product Brand (5 fields); owners are no longer a routing or display concept on the cockpit. Deployed FULLUAT + KJDEV.

## 2026-07-21 (later still) — "Route does nothing" + component crash → picker rebuild (deployed FULLUAT & KJDEV)

Kamyar's screenshot solved it: **the quality card CRASHED** ("Cannot read properties of undefined (reading 'activeSubs')") on "UAT Converted" — a contact-linked record with `Account_Contact__c` null (created already-closed, so PFC_On_Save never stamped it) → contact mode with no firm → unguarded `{firm.activeSubs}` template binding. The crash overlay is what made the page/actions feel dead.

Fixes (Apex 9/9, Jest 5/5, both orgs):
1. **Controller fallback**: when the account stamp is missing, firm context resolves via `Contact__r.AccountId` (+ its Ultimate). `buildFirmContext` refactored to take resolved office/ultimate params. Regression test `contactModeFallsBackToContactsAccountWhenStampMissing` (asserts the closed-at-birth premise explicitly).
2. **LWC guard**: contact-mode firm bindings wrapped in `showFirmContext`; graceful `data-id="no-account"` state when a contact has no account at all (Jest-covered; the Apex equivalent is untestable here — org VR "Please add the Account to the Contact record" is not bypass-aware).
3. **Routing flow v2 — team PICKER (Kamyar's ask)**: `PFC_Route_to_Account_Team` now shows a radio list of the firm's account-team members (User collection choice set, sorted by name) with an optional note; router chooses. Same office→Ultimate resolution + the new Contact-account fallback. No-team path unchanged (firm owner + explicit warning). Auto-pick-by-role dropped; `Route_Preferred_Roles__c` CMDT field retained for a future default-selection enhancement. Flow runs `SystemModeWithoutSharing` so reps reliably read team membership (read-only routing data, ATM precedent).

GOTCHAS this round: Apex escapes quotes with backslash not doubling; flow collection choice sets = `dynamicChoiceSets` + `collectionReference`; Get Records `In` operator takes a text collection.

Remaining intentional deltas vs mockup: Log Outreach lives in Activity composer (platform limit); Lead/Contact sidebar context card deferred to the Phase D LWC (Update-action gack); Days_to_Conversion hidden until Opp linked (mockup shows it empty); lead-linked primary action is Convert Lead (converts lead) rather than a direct Create Opp. Mockup §3 (Lead Quality / Account Context card) and the contact-variant "Firm completions — 90 days" sidebar list are Phase D scope — the mockup supplies the copy, badge set, gauge design, and entitlement-flag wording for D1/D2. Prod checklist additions: create 'CRM Support' Chatter group (or point CMDT at an existing one), System.schedule the sweep, assign PFC_Triage_Cockpit_Fields to triage users, deactivate the 2 WFRs in the same window as activating the new stamp flow version (double-stamp is harmless but un-stamp isn't), verify Pardot connector task-assignee default (open Q #4).
