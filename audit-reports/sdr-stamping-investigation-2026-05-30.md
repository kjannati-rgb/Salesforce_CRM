# Opportunity `Sales_Development_Representative__c` Stamping — Diagnostic Report

**Date:** 2026-05-30
**Author:** Automated investigation (read-only)
**Org:** **PRODUCTION** — `kamyar.jannati@lbresearch.com`, `https://lawbusinessresearch.my.salesforce.com`, Org Id `00D6g0000081IOgEAM` (confirmed via `sf org display` before any query).
**Scope:** Why the Opportunity lookup `Sales_Development_Representative__c` is frequently out of sync with the OpportunityTeamMember (OTM) whose `TeamMemberRole = 'Sales Development Representative'`.
**Nature:** Read-only. No metadata was modified or deployed; no records were changed. Production was queried (SOQL + Tooling API) and three flows were inspected.

---

## TL;DR

- There is **no active, automatic (record-triggered) automation that stamps the SDR lookup**. The only flow built for that job, `OpportuintyTeam_AfterSave`, exists as **a single version that is `Obsolete` — it was never activated**.
- The **only** thing that stamps `Sales_Development_Representative__c` is the **manual "Opportunity Team Widget" screen flow** (`Create_Opportunity_Contacts`, Active v21). It stamps **only when an SDR team member is added through that widget**.
- Any SDR team member added **any other way** — standard "Opportunity Team Members" related list, Data Loader/API/ALM, or the **renewal team-copy flow** — leaves the lookup **blank**. That is the mechanism behind the ~553 blanks.
- The active renewal flow `Opportunity_Sync_Opportunity_Team` (v2) **copies SDR team members from the previous opportunity and stamps `Client_Engagement_Director__c` and the CS Contact field — but was never wired to stamp the SDR lookup.** A direct, currently-live asymmetry that guarantees renewals drift.
- No custom Apex is involved: the only trigger on OpportunityTeamMember is `RHX_OpportunityTeamMember` (the managed **Rollup Helper** package).
- **Current state (post your manual backfill):** 0 blank-despite-member, 0 lookup-without-member, **6 multi-SDR opportunities** remain. **The drift will recur**, because nothing automatic stamps non-widget adds.

---

## 1. Automation that touches `Sales_Development_Representative__c`

A whole-project search of local SFDX source for the field API name and the string `Sales Development Representative` returned exactly **three** flows; production Tooling API confirmed their live status and versions.

| # | Flow (API name) | Label | Type | Trigger / invocation | Live status (prod) | Writes SDR lookup? | File |
|---|---|---|---|---|---|---|---|
| 1 | `Create_Opportunity_Contacts` | "Opportunity Team: Create/Remove Team Member Screenflow" | **Screen Flow** | Manual — custom "Opportunity Team Widget" on Opportunity | **Active (v21, since 2026-04-20)** | **Yes** (on manual add) | [Create_Opportunity_Contacts.flow-meta.xml](../force-app/main/default/flows/Create_Opportunity_Contacts.flow-meta.xml) |
| 2 | `OpportuintyTeam_AfterSave` (note typo "Opportuinty") | OpportuintyTeam_AfterSave | Record-Triggered (Autolaunched) | OpportunityTeamMember, after-save, Create **and** Update | **Obsolete — only v1 ever existed; never activated** | Would have (inactive) | [OpportuintyTeam_AfterSave.flow-meta.xml](../force-app/main/default/flows/OpportuintyTeam_AfterSave.flow-meta.xml) |
| 3 | `OpportunityTeam_Delete` | OpportunityTeam_Delete | Record-Triggered (Autolaunched) | OpportunityTeamMember, before-delete | **Obsolete — v1 only; never activated** | Clears it (inactive) | [OpportunityTeam_Delete.flow-meta.xml](../force-app/main/default/flows/OpportunityTeam_Delete.flow-meta.xml) |

**Adjacent flow that matters (does NOT write the SDR lookup but creates SDR team members):**

| Flow | Label | Type | Live status | Behaviour |
|---|---|---|---|---|
| `Opportunity_Sync_Opportunity_Team` | `Opportunity_AL_SyncOpportunityTeamMembers` | Autolaunched (subflow, invoked on new Opportunity) | **Active (v2, since 2026-04-21)** | On a **new renewal** opp (`Previous_Opportunity__c` set), **copies all OTMs (including SDR) from the previous opp**, then stamps `Client_Engagement_Director__c` and `CS_Contact__c` on the new opp — **but not `Sales_Development_Representative__c`**. |

**Apex:** The only trigger on OpportunityTeamMember is `RHX_OpportunityTeamMember` (managed **Rollup Helper** package — not a stamper). Opportunity has several triggers (`OpportunityBefore`, `OpportunityTrigger`, `OpportunityAfter`, `Ast_OpportunityTrigger`, `OpsosOpportunityTrigger`, `OpportunityTriggerMBLChangeEvent`, `OpportunityTR`, `RHX_Opportunity`), but the SDR value is sourced **from** OTM, and there is no custom OTM-side Apex to stamp it. **No custom Apex stamps this field.**

Flow version evidence (Tooling API `Flow`):
```
Create_Opportunity_Contacts        v1–v20 Obsolete, v21 ACTIVE (2026-04-20)
OpportuintyTeam_AfterSave          v1 ONLY — Obsolete (2026-04-20)   ← never activated
OpportunityTeam_Delete             v1 ONLY — Obsolete (2026-04-20)   ← never activated
Opportunity_Sync_Opportunity_Team  v1 Obsolete, v2 ACTIVE (2026-04-21), v3 Obsolete
```

---

## 2. How each automation behaves

### #1 `Create_Opportunity_Contacts` — the ONLY active SDR stamper (manual widget)

Screen flow launched from the Opportunity ("Opportunity Team Widget"). `runInMode = SystemModeWithoutSharing`.

**Add an SDR:**
1. User picks "Add User", selects a User, Team Role = `Sales Development Representative`.
2. `Get_All_sdrs`: existing SDR OTM on the opp (`getFirstRecordOnly = true`).
3. `Does_sdr_exist`: **if one already exists → error screen "Sales Development Representative already Exist, please remove the existing to add new"; nothing is created or stamped.** (The widget enforces *at most one* SDR.)
4. Else → create the OTM → `Copy_1_of_Update_Opportunity` sets `Sales_Development_Representative__c = User.recordId`.
   - The update is filtered by `Opportunity_Salesforce_ID__c = recordid` (not by `Id`). If that text field is blank/incorrect, the update silently matches nothing and the stamp is lost. **(fragility)**

**Remove an SDR (via widget):** deletes the selected OTM, then `Check_if_removed_sdr_match`: clears `Sales_Development_Representative__c` **only if** it equalled the removed member's UserId. A stale/different value is left as-is.

**Match:** exact, case-sensitive `Sales Development Representative`. No trim/normalise. **Overwrite:** never blind-overwrites (it blocks a 2nd SDR instead).

### #2 `OpportuintyTeam_AfterSave` — the intended automatic stamper, NEVER ACTIVATED

- Designed for OpportunityTeamMember after-save, `CreateAndUpdate` → on role `Sales Development Representative`, `Update_SDR` sets `Sales_Development_Representative__c = $Record.UserId` (unconditional overwrite). Also handles CED and aggregates CS Contact.
- **Production has only v1, status `Obsolete`** (created and obsoleted on 2026-04-20). **It has never run.** Had it been activated, it would have stamped *every* SDR OTM insert/update regardless of channel — exactly the population now found blank.

### #3 `OpportunityTeam_Delete` — the intended un-stamper, NEVER ACTIVATED

- Designed to clear `Sales_Development_Representative__c` (and CED) on OTM delete. **v1 only, `Obsolete`.** Never run → deleting an SDR member outside the widget leaves the lookup stale.

### #4 `Opportunity_Sync_Opportunity_Team` v2 (ACTIVE) — copies SDR members, stamps CED/CS but NOT SDR

- Invoked on **new** Opportunity creation for renewals (`recordId.Previous_Opportunity__c`).
- `Get_Previous_Opportunities_Team_Member` → `Transform_to_create_opportunity_team_member` → **creates OTMs** mapping `UserId`, `TeamMemberRole` (incl. `Sales Development Representative`), `OpportunityAccessLevel` onto the new opp.
- `Update_Opportunity_record_for_cs_contacts` sets:
  - `CS_Contact__c = <aggregated CS names>`
  - `Client_Engagement_Director__c = Previous_Opportunity__r.Client_Engagement_Director__c`
  - **(no assignment for `Sales_Development_Representative__c`)**
- Net effect: **every renewal copies the SDR team member but leaves the SDR lookup blank**, while CED and CS Contact are stamped. This is a concrete, currently-live source of drift.

---

## 3. Why ~553 opportunities had an SDR team member but a blank lookup — confirmed

**Root cause:** No active automatic stamper exists. The only stamping path is the **manual widget**, which fires only when an SDR member is added through it. Every other channel leaves the lookup blank:

- **Standard "Opportunity Team Members" related list** adds (native UI).
- **Renewal team-copy flow** (`Opportunity_Sync_Opportunity_Team`, active) — copies SDR members but doesn't stamp the lookup.
- **Data Loader / API / ALM migration.**

The catch-all flow that would have covered all of these (`OpportuintyTeam_AfterSave`, after-save Create+Update) **was authored but never activated** (only an `Obsolete` v1 exists).

**Supporting evidence from production:**

- **SDR OTM volume & timing** — role usage began 2025-08 and ramped; total ≈ 857:

  | Period | Count | | Period | Count |
  |---|---|---|---|---|
  | 2025-08 | 14 | | 2026-01 | 90 |
  | 2025-09 | 23 | | 2026-02 | 151 |
  | 2025-10 | 53 | | 2026-03 | 136 |
  | 2025-11 | 61 | | 2026-04 | 149 |
  | 2025-12 | 71 | | 2026-05 | 109 |

  (2025 total 222; 2026 total 635.) From the first SDR usage (2025-08) through the audit, **no automatic stamper was ever active** (the would-be flow's only version is Obsolete; the renewal flow doesn't stamp SDR). So blanks accumulated across the whole period for every non-widget add → ~553.

- **Creators are many individual reps**, not a single integration/migration user (top: Imogen Eisenmann 98, Reece Jordan 74, Thomas Gazey 72, Saurabh Patil 65, …). So the gaps are **everyday rep activity through non-stamping channels**, not one bulk load. (The "ALM bulk migration" hypothesis is **not** the primary driver, though any bulk insert would also have been missed.)

**Hypotheses from the brief — verdicts:**

| Hypothesis | Verdict (production evidence) |
|---|---|
| Flow activated *after* most 553 were created | **Stronger than that:** the automatic stamper was **never activated at all** (v1 Obsolete). Nothing to "miss the window" — there was no window. |
| Fires only on INSERT, so bulk/migrated members never triggered it | The active stamper (widget) fires only on manual widget use, not on insert. Bulk/renewal/standard-UI inserts are unstamped. |
| Bulk-DML / integration-user / bypass path skips it | No bypass needed — there is no active record-triggered automation to bypass. Creators are mostly named reps, not an integration user. |
| Was deactivated for a period | The would-be stamper was never active; the renewal flow (active) simply omits the SDR field. |

---

## 4. Edge-case behaviour (production-confirmed)

- **Multiple SDR team members on one Opportunity:** the widget blocks a 2nd SDR, so multi-SDR opps were necessarily created outside the widget. **6 such opportunities currently exist** (`006Px00000QM3rVIAT`, `006Px00000OyhtuIAB`, `006Px00000O2KzSIAV`, `006Px00000PojtCIAR`, `006Px00000Q9DrtIAF`, `006Px00000ObqoGIAR`). No automation reconciles them; the lookup (if set) reflects a single nondeterministic add.
- **Role change on an existing team member:** no active automation reacts (the after-save flow that handled Update is Obsolete). Lookup goes stale.
- **Team-member removal:** only the widget Remove path clears the lookup, and only when it matched; standard/Data Loader delete leaves it stale (delete flow Obsolete). Currently **0** lookup-without-member (your backfill cleaned these), but the mechanism remains.
- **Renewal / clone:** the active renewal flow copies the SDR member but does **not** stamp the lookup → renewals are structurally guaranteed to be out of sync until manually fixed.
- **The "1 different user" case:** consistent with a member swap/role change outside the widget — old value never overwritten (no active overwrite path).

**Current sync state (post manual backfill):**
- SDR member but blank lookup: **0**
- Lookup set but no SDR member: **0**
- Multi-SDR opportunities: **6**

---

## 5. Failures / error logs

No dedicated check of FlowInterview / paused-failed interviews was run in this pass (the primary stamper is a screen flow with no record-trigger faults, and the would-be auto-flow never ran). The active renewal flow has a `faultConnector` to `Opportunity_Fault_Email` — if renewals were failing to copy teams, those would surface there. Recommend a follow-up scan of Setup → Paused And Failed Flow Interviews and `FlowInterview` for `InterviewLabel LIKE 'Opportunity_AL_SyncOpportunityTeamMembers%'` if renewal team-copy reliability is in question.

---

## 6. Recommended fixes (described only — NOT implemented)

1. **Close the structural gap — stamp on the OTM record automatically.** Activate a corrected version of `OpportuintyTeam_AfterSave` (after-save, **Create + Update**) so the SDR lookup is stamped regardless of channel (standard UI, Data Loader, API, renewal copy). This is the single highest-impact fix; without it the field will keep drifting.
2. **Re-activate delete handling** (corrected `OpportunityTeam_Delete`) so removing the SDR member clears the lookup instead of going stale.
3. **Quick parity fix for renewals (low effort):** add a `Sales_Development_Representative__c` assignment to the active `Opportunity_Sync_Opportunity_Team` v2 mirroring the existing `Client_Engagement_Director__c` line — eliminates the renewal-specific blanks immediately. (Still recommend #1 as the general solution.)
4. **Decide overwrite policy explicitly.** The auto-flow design blind-overwrites; the widget never overwrites. Recommend "set to the current sole SDR member" with a defined multi-SDR rule (e.g. most-recent wins) plus a data-quality flag, rather than nondeterministic behaviour.
5. **Match by `Id`, not `Opportunity_Salesforce_ID__c`,** in all the Opportunity update elements to remove the silent-miss fragility.
6. **Robust role matching** (trim/normalise or compare to the canonical picklist value) to avoid case/whitespace misses.
7. **Backfill:** already done manually (confirmed: 0 blanks now). Once #1 (or at least #3) is live, drift won't re-accumulate. Recommend a scheduled reconciliation report (lookup vs sole SDR OTM) as a safety net, and a one-off cleanup of the **6 multi-SDR** opportunities.

---

## Appendix — exact commands/queries used (re-runnable, read-only)

**Auth / confirm prod:**
```
sf org login web -r https://login.salesforce.com -a LBR_PROD
sf org display -o LBR_PROD          # confirmed username kamyar.jannati@lbresearch.com, my.salesforce.com
```

**Flow versions & live status (Tooling API):**
```
sf data query -o LBR_PROD -t -q "SELECT Definition.DeveloperName, VersionNumber, Status, ProcessType, LastModifiedDate FROM Flow WHERE Definition.DeveloperName IN ('Create_Opportunity_Contacts','OpportuintyTeam_AfterSave','OpportunityTeam_Delete','Opportunity_Sync_Opportunity_Team') ORDER BY Definition.DeveloperName, VersionNumber"
```

**Active v2 sync-flow metadata (to confirm it does NOT write the SDR field):**
```
sf data query -o LBR_PROD -t -q "SELECT Metadata FROM Flow WHERE Id='301Px00000XHAcfIAH'" --json
# → writes Client_Engagement_Director__c and CS_Contact__c; NOT Sales_Development_Representative__c
```

**Apex triggers on the two objects:**
```
sf data query -o LBR_PROD -t -q "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE TableEnumOrId IN ('OpportunityTeamMember','Opportunity')"
```

**SDR OTM volume by month:**
```
sf data query -o LBR_PROD -q "SELECT CALENDAR_YEAR(CreatedDate) yr, CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt FROM OpportunityTeamMember WHERE TeamMemberRole='Sales Development Representative' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate) ORDER BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)"
```

**Out-of-sync population (current):**
```
sf data query -o LBR_PROD -q "SELECT COUNT(Id) FROM OpportunityTeamMember WHERE TeamMemberRole='Sales Development Representative' AND Opportunity.Sales_Development_Representative__c = null"   # → 0
sf data query -o LBR_PROD -q "SELECT COUNT(Id) FROM Opportunity WHERE Sales_Development_Representative__c != null AND Id NOT IN (SELECT OpportunityId FROM OpportunityTeamMember WHERE TeamMemberRole='Sales Development Representative')"   # → 0
sf data query -o LBR_PROD -q "SELECT OpportunityId, COUNT(Id) c FROM OpportunityTeamMember WHERE TeamMemberRole='Sales Development Representative' GROUP BY OpportunityId HAVING COUNT(Id)>1"   # → 6 opps
```

**Creators:**
```
sf data query -o LBR_PROD -q "SELECT CreatedBy.Name n, COUNT(Id) c FROM OpportunityTeamMember WHERE TeamMemberRole='Sales Development Representative' GROUP BY CreatedBy.Name ORDER BY COUNT(Id) DESC"
```

**Local source inspected:** `force-app/main/default/flows/{Create_Opportunity_Contacts, OpportuintyTeam_AfterSave, OpportunityTeam_Delete, Opportunity_Sync_Opportunity_Team}.flow-meta.xml` (note: local copy of the sync flow was the obsolete version; the **active v2 was fetched from production** as above).
