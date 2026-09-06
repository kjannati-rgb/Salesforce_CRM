# PFC Triage Cockpit — Production Deployment Runbook (Phase F3)

**Precondition:** UAT exit criteria met (UAT-SCRIPT.md) + Gates C/D decisions answered (Brand_Family_Map rows, gauge bands, SLA threshold/alert group, Convert-Lead-on-DQ visibility, Path copy).
**Every numbered step requires explicit human confirmation before execution.** No step is optional to skip silently — record deviations here.
**Source of truth:** `pfc-triage-cockpit/kjdev-build/` + manifest `rev-package.xml`. Rollback notes inline. Org: PROD alias `PROD` (`00D6g0000081IOgEAM`) — verify with `sf org display --target-org PROD` first (session protocol).

## Known prod-specific facts baked into this plan
- Prod deploys flows as **Draft** (org setting OFF) → activation is an explicit FlowDefinition step.
- Prod has pre-existing red tests → deploy with **RunSpecifiedTests** (`PFCRoutingSlaServiceTest`, `PFCQualityCardControllerTest`), never RunLocalTests.
- The old page (`Pardot_Form_Completion_Record_Pagev2`) is pinned via **`standard__LightningSales` / `standard__LightningSalesConsole` profileActionOverrides** which beat the org default — activation MUST patch those (retrieve fresh from prod, patch Form_Completion-RT + RT-less blocks only, leave Newsfeed/Scored_Leads on v2, redeploy). Same procedure as KJDEV (BUILD-LOG 2026-07-15).
- CustomObject deploys must use the **bare object-meta.xml** (bundling recordTypes trips the `Reason_Disqualified__c` NBSP picklist mismatch).
- The two `Date_Completed` Workflow Rules and the new `PFC_Stamp_Work_Fields` version must swap in the **same activation window** (both live = double stamping; neither = no stamping).

## Phase 0 — Pre-deploy (day before)
1. `sf org display --target-org PROD` — confirm org ID `00D6g0000081IOgEAM`.
2. Retrieve prod backups into `pfc-triage-cockpit/prod-backup-<date>/`: both Layouts, `Workflow:Pardot_Form_Completion__c`, `Flow:Pardot_Create_PFC_Orchestrator`, `Flow:PFC_Stamp_Work_Fields`, `CustomObject:Pardot_Form_Completion__c`, `CustomApplication:standard__LightningSales`, `CustomApplication:standard__LightningSalesConsole`. These ARE the rollback artifacts.
3. Confirm/create Chatter group named per `PFC_Settings.Default.Alert_Chatter_Group__c` (default "CRM Support") — sweep fail-opens without it (flags but no alert).
4. Business sign-off recorded on `Brand_Family_Map__mdt` rows and `PFC_Settings` values.

## Phase 1 — Deploy body (inert)
5. Dry run: `sf project deploy start --manifest pfc-triage-cockpit/rev-package.xml --source-dir pfc-triage-cockpit/kjdev-build --target-org PROD --dry-run --test-level RunSpecifiedTests --tests PFCRoutingSlaServiceTest --tests PFCQualityCardControllerTest` (if manifest+source-dir conflict, deploy the kjdev-build dir with the same test flags; the dir contains exactly the feature set plus the two KJDEV-only object patches which must be EXCLUDED — see step 6 note).
6. Real deploy, same flags. **Inert on arrival:** flows Draft, page unassigned, WFR file — ⚠ the Workflow deploy DOES apply `active=false` immediately. Therefore: **deploy the Workflow component only in Phase 2** (remove `workflows/` from the body deploy; the manifest keeps it listed for completeness — deploy it with `--source-dir .../workflows` at step 10). Nothing else changes runtime behaviour.
   - Note: `kjdev-object-clean/` and `kjdev-apps/` folders are KJDEV-state files — never deploy them to prod.
7. Verify both test classes green in the deploy result; `Routing_Overdue__c` FLS exists only via the two permsets (expected).
8. Assign permsets: `PFC_Triage_Cockpit_Fields` to the rep population (same grantees as `PFC_REV57_Field_Access`); `PFC_Clay_Integration` to NOBODY (waits for the Clay integration user).

## Phase 2 — Activate automation (one flow at a time, Flow_Log watch between each)
9. Activate `Pardot_Create_PFC_Orchestrator` new version via FlowDefinition deploy. Smoke: insert a `PFC: Runbook Smoke` Task → PFC created owned by **PFC Triage Queue**, Sales_Rep blank. Watch `Flow_Log__c` 15 min. *Rollback: FlowDefinition → previous version number (see backup).*
10. Deploy `workflows/Pardot_Form_Completion__c.workflow-meta.xml` (deactivates both WFRs) **and immediately** activate the new `PFC_Stamp_Work_Fields` version. Smoke: disqualify the smoke PFC (with reason) → Date_Completed stamped once; reopen → stamp survives. *Rollback: redeploy backup workflow file (rules active=true) + FlowDefinition stamp flow → previous version.*
11. Activate `PFC_Disqualify` and `PFC_Route_to_Account_Owner` (screen flows). Quick action smoke on the test record.
11b. Activate the new `Pardot_Form_completion_Create_task_based_on_Next_Contact_date` version (UAT fix: task owner falls back to the editing user when the PFC is queue-owned — WITHOUT this, setting Next Contact Date on any queue-owned record FAILS the whole save with "Queue not associated with this SObject type"). Must go live in the same window as the orchestrator queue-default (step 9).
12. Schedule the sweep: `System.schedule('PFC Routing SLA Sweep', '0 0 * * * ?', new PFCRoutingSlaSweepSchedulable());` (anonymous Apex, one-liner). Verify CronTrigger exists. *Rollback: abort the CronTrigger; or set `PFC_Settings.Sweep_Disabled__c = true` (CMDT deploy) to neuter without unscheduling.*

## Phase 3 — Activate the page (last)
13. Retrieve prod `CustomObject:Pardot_Form_Completion__c`, patch the three View actionOverrides `Pardot_Form_Completion_Record_Pagev2` → `PFC_Triage_Cockpit_Record_Page`, deploy the **bare object file**.
14. Retrieve prod `standard__LightningSales` + `standard__LightningSalesConsole`, patch v2→cockpit for Form_Completion-RT and RT-less profileActionOverrides blocks only, deploy. (ALM / MBL_Seminars / Newsfeed / Scored_Leads assignments untouched.)
15. Verify as a REP user (not admin): open a live Form_Completion record — cockpit renders, quality card loads < ~1s incl. on a Clifford-Chance-scale firm record (Gate D item not testable in KJDEV). Newsfeed record still renders v2.
    *Rollback: redeploy backup object file + backup app files — instant revert to v2, zero data impact.*

## Phase 4 — Post-go-live checks
- **Day 1:** % of PFCs created today owned by PFC_Triage_Queue (target 100%); zero new records with Sales_Rep = Saurabh Patil; Flow_Log clean; sweep ran hourly (CronTrigger NextFireTime advances); no Routing_Overdue false-positives during working hours.
- **Day 7:** queue-dwell distribution (are 4 working hours right?); Routing_Overdue flag+clear counts; Disqualify action usage vs manual stage edits; duplicate-warning click feedback from reps; entitlement-flag accuracy feedback from KA team.
- **Day 30:** success-criteria table from PHASE-A-FINDINGS §5 (re-anchored baselines).

## Dependency: firm Account Teams (Route to Account Team)
Routing for contact-linked PFCs targets the **Firm account's Account Team**, recipient chosen by `PFC_Settings__mdt.Route_Preferred_Roles__c` (CSV, priority order; currently "LexPro BDM" — the only role that exists). **BD / SDR team roles are not set up yet (Kamyar, 21-Jul)** — when they are:
1. Add the members to Firm-record-type accounts' teams with the new roles.
2. Update `Route_Preferred_Roles__c` on the Default PFC Settings record (config change, no deploy), e.g. `BD,SDR,LexPro BDM`.
Until then, firms without any team fall back to the firm owner with an explicit warning in the routing dialog — expect that path to be common at go-live; it is visible, not silent. Day-7 check: % of routes hitting the fallback.

## Explicitly out of this deployment
- PFC_Source backfill (PFC-SOURCE-BACKFILL-PROPOSAL.md — own approval).
- Funnel-counter field retirement (inventory delivered; goes through the field-retirement taxonomy).
- Clay return-leg build (Ashton/Clay-side; SF is ready: queue + permset + fields).
- Pardot connector task-assignee change (optional lever, decide separately).
- List-view cull of the ~150 legacy views (recommend separate ticket).
