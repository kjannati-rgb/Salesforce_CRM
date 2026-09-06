# REV-57 — Phase 0 Audit Findings

**Date:** 2026-06-10 · **Org audited:** Production `LBR_PROD` (kamyar.jannati@lbresearch.com) · **Mode:** retrieve-only
**Retrieved to:** `rev57/audit/` (5 flows + `Pardot_Form_Completion__c` full object)

> STATUS: Phase 0 complete pending one optional read-only sweep (see §6). **Stop point — review with Kam before Phase 1.**

---

## 0. Org-alias correction (do not skip)

The runbook assumes aliases `prod` / `kjdev`. **They do not exist.** Real aliases:

| Role | Alias | Username | Default? |
|------|-------|----------|----------|
| Production | **`LBR_PROD`** | kamyar.jannati@lbresearch.com | No |
| Sandbox | **`KJDEV`** | kamyar.jannati@lbresearch.com.kjdev | **Yes (U)** |

⚠️ **KJDEV is the default org.** Any bare `sf` command hits the sandbox. Production work must pass `--target-org LBR_PROD` explicitly. (`--target-org prod` from the runbook would error.)

---

## 1. HEADLINE: Flow (1) has NO Newsfeed branch

The runbook says *"Assume flow (1) already contains a Newsfeed branch referencing the Newsfeed_Subscribers record type."* **This is false.**

`Create_Pardot_Form_from_Task` (apiVersion 54.0, **Active**, last mod 2026-04-17 by Saurabh Patil) fires on **exactly three** subject prefixes and contains no `NF -`, no Newsfeed string, and no reference to the Newsfeed_Subscribers RT (`012Px000003AadBIAS`). Grep across all 5 retrieved flows: zero Newsfeed hits.

**Implication:** the 17-Apr prototype PFC (`a5EPx00000W7743MAB`) was created by **B2BMA Integration** (Pardot connector writing the PFC directly), *not* by this flow. The Salesforce-side Newsfeed path is **greenfield** — the rebuild builds it, it isn't extending an existing branch. This also re-frames **D5**: confirm whether Pardot is configured to emit an `NF -` **Task** (which the new orchestrator consumes) vs. continuing to write PFC records directly via B2BMA (which would bypass the flow entirely).

---

## 2. Flow (1) entry criteria & logic (the real contract to preserve)

**Trigger:** Task, `RecordAfterSave`, **Create only**. Scheduled async path `Async_Path`: offset **+1 min** from `CreatedDate`, `maxBatchSize 50`.

**Start filter (`OR`):** `Subject StartsWith` one of:
- `PFC:`  (note the colon)
- `Lead scoring MQL`
- `EVT`

**Kill switch:** custom setting `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` → if true, skips creation.

**Derived values (formulas):**
- `record_type` = `CONTAINS(Subject,"PFC")` → Form_Completion `012Tm000000xaVhIAI`; elif `CONTAINS(Subject,"Lead scoring MQL")` → Scored_Leads `012Tm000000xaViIAI`; **else** → Events_Sponsorship `012Px0000030WhKIAU`. **Hardcoded IDs** — confirms the NFR to resolve RTs by DeveloperName via CMDT.
- `Form_Name` = subject with `"PFC:"` or `"Lead scoring MQL:"` stripped. ⚠️ This is subject-parsing — fine for inbound, but the locked decision forbids it for newsfeed.

**Fields stamped on Create (only 4):**
| Field | Value |
|---|---|
| `Form_Name__c` | `Form_Name` formula |
| `RecordTypeId` | `record_type` formula |
| `Sales_Rep__c` | `$Record.OwnerId` (Task owner) |
| `Sales_Stage__c` | `"New"` (hardcoded) |

**Then:** re-query created PFC → decision `isLead?` on `WhoId StartsWith "00Q"`:
- Lead → set `Lead__c = WhoId`
- else (Contact) → set `Contact__c = WhoId`

**NOT set by this flow:** `Brand__c` (formula, derived), `Campaign__c`, `Date_Completed__c`, any source field, `OwnerId` (PFC owner left to default/ROE). So "preserve all field population flow (1) does" (Phase 2) = **just these 4 fields + the WhoId→Lead/Contact link.** Simpler than the runbook implies.

---

## 3. Brand__c is derived from Form_Name__c — and that breaks cross-linking for newsfeed

`Brand__c` is a **formula** (Text): `CONTAINS(TEXT(Form_Name__c), "Lexology"/"GAR"/"GCR"/...)` → brand, else `"Other"`. It keys **entirely off `Form_Name__c`**.

Newsfeed records have `Form_Name__c = null` → formula returns **"Other"** (matches the prototype). 

**Consequence for the core feature:** the cross-link match key is *same person + same brand-grain product + open stage*. If matching used `Brand__c`, every newsfeed record collapses to "Other" and would mis-match unrelated "Other" inbounds. **Therefore D1's new field `Product_Brand__c` is not merely "recommended" — it is a hard dependency** for correct cross-linking. Extending the Brand formula is not viable (it can't see a stamped value without a real Form_Name, which we're forbidden to parse).

---

## 4. Suite flows (2)/(3)/(5) — source-agnostic confirmed (partially)

Grep for `RecordType` / `Newsfeed` / hardcoded `012` IDs in `On_Pardot_Form_Creation` and `Move_Lead_to_Contact_on_Pardot_Form`: **zero matches.** No record-type branching, no newsfeed coupling found → consistent with the runbook's assumption that they're safe to leave untouched. (Full field-flow trace deferred; flag if Phase 2 adds required fields they don't populate.)

---

## 5. Record-type rename target

`Newsfeed_Subscribers` (Id `012Px000003AadBIAS`, **active**, label "Newsfeed Subscribers", desc "Records created via Free Newsfeed Subscribers sign-ups"). Carries picklist value assignments for `Form_Name__c` (45 values), `Reason_Disqualified__c`, `Sales_Stage__c`.

Rename target: label **"Newsfeed Registrations"**, DeveloperName **`Newsfeed_Registrations`**. The DeveloperName change is the risky bit — anything referencing the API name `Newsfeed_Subscribers` breaks. **Local retrieve shows zero references in the 5 flows + PFC object.** Broader prod inventory still owed (§6).

---

## 6. Reference sweep — COMPLETE (2026-06-10, read-only prod)

**Verdict: the DeveloperName rename `Newsfeed_Subscribers` → `Newsfeed_Registrations` is SAFE.** No Apex, active flow, or declarative component references the RT by DeveloperName or by Id.

Key principle applied: **ID-bound references survive a DeveloperName rename** (list views, reports, layout RT assignments all bind to the stable 18-char Id `012Px000003AadBIAS`). Only **DeveloperName string-literal** references break (Apex `...ByDeveloperName`, flow lookups/decisions on `RecordType.DeveloperName`, formula/VR string comparisons). The sweep targeted those.

| Surface | Method | Result |
|---|---|---|
| Apex (classes + triggers) | Tooling SOSL `FIND {Newsfeed_Subscribers}` and `FIND {012Px000003AadBIAS}` | **0 hits** |
| Declarative component refs to the RT | `MetadataComponentDependency WHERE RefMetadataComponentId='012Px000003AadBIAS'` | **0 rows** |
| Flows touching PFC object | `MetadataComponentDependency` (RefId = PFC object `01I4L000001GqMNUA0`) → 11 distinct flows | only suite flows + Opp-side flows |
| — active PFC flows | retrieved & grepped each | 5 suite flows + `Opportunity_Renewal_New_Records` — **all clean** |
| — inactive PFC flows | `Add_Contact_Roles_to_Opportunity`, `Opportunity_Object_Create_Edit`, `ScheduleProcessBuilderMigrate` | inactive; no RT-component dep; not runtime risks |
| PFC object metadata (fields/VRs/list views/compact layout) | local grep of full retrieve | only the RT file itself mentions "Newsfeed" |

Org scale for context: **1,619 flow versions, 159 active flows**, but only 11 reference PFC.

**Residual (non-blocking) items:**
- **Reports/dashboards** filtered/grouped by this RT bind to the Id → survive the rename; the new **label** "Newsfeed Registrations" just displays. Cosmetic only, no breakage.
- **Pardot / B2BMA connector** (external to SF metadata) created the prototype PFC directly — must be reviewed manually. This *is* decision **D5** and is the real architectural fork (see §1).
- 3 inactive PFC flows not opened (no RT dependency detected); revisit only if reactivated.

---

## 7. Net corrections to the runbook

1. Aliases: `LBR_PROD` / `KJDEV`, KJDEV is default. (§0)
2. Flow (1) has **no** Newsfeed branch — NF path is greenfield, prototype came from B2BMA. (§1)
3. Flow (1) handles **three** sources (PFC:, Lead scoring MQL, EVT) → the unified orchestrator's CMDT must seed all three to replace it, plus NF. (§2)
4. Field population to preserve = 4 fields + WhoId link, not a large set. (§2)
5. `Product_Brand__c` (D1) is a **hard dependency** of cross-linking, not optional — `Brand__c` returns "Other" for newsfeed. (§3)
6. D5 reframed: confirm Pardot emits an `NF -` Task vs. writing PFC directly via B2BMA. (§1)
