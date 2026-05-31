# Opportunity SDR Field — UX Improvement (SANDBOX KJDEV)

**Date:** 2026-05-30
**Org (target):** **SANDBOX** — `kamyar.jannati@lbresearch.com.kjdev`, Org Id `00DAe00000D35gVMAR`, `https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com`. Confirmed via `sf org display -o KJDEV` before any action. **Not production** (prod is `00D6g0000081IOgEAM`).
**Status:** Read-only investigation + backup complete. **No metadata deployed yet** — Step 2 deployment is paused pending your decisions (see end).

---

## Step 0 — Dependency check (BLOCKER, flagged)

The auto-stamp flow this UX work depends on is **NOT active in KJDEV**:

```
sf data query -o KJDEV -t -q "SELECT Definition.DeveloperName, VersionNumber, Status
  FROM Flow WHERE Definition.DeveloperName='OpportuintyTeam_AfterSave'"
→ v1, Status = Obsolete   (no active version)
```

Related flow states in KJDEV (for context):

| Flow | Role | KJDEV status |
|---|---|---|
| `OpportuintyTeam_AfterSave` | auto-stamp on all channels (**the dependency**) | **Obsolete — not active** |
| `Create_Opportunity_Contacts` | "Opportunity Team Widget" — writes SDR on manual add (system context) | Active v21 |
| `Opportunity_Sync_Opportunity_Team` | renewal team-copy — does **not** write SDR lookup | Active v2 |
| `OpportunityTeam_Delete` | clears field on OTM delete | Obsolete — not active |

**Implication:** if the field is made read-only *before* the auto-stamp flow is live, SDRs added via the **standard related list** or copied by the **renewal flow** will leave the field blank, and users **cannot hand-fix it**. Only the widget would keep it populated. This is the exact risk Step 0 asked me to surface → deployment paused.

---

## Step 1 — Retrieve & backup (done)

Backed up before any edit:
- **Immutable metadata-format zip:** `backup/sdr-ux-2026-05-30/metadata-zip/unpackaged.zip`
- **Pristine source copies:** `backup/sdr-ux-2026-05-30/source-original/{layouts,compactLayouts,fields}/`
- **Manifest used:** `backup/sdr-ux-2026-05-30/package.xml`

Components retrieved (KJDEV):
- **Page layouts (5):** `Opportunity-New Business Opportunities`, `Opportunity-ALM - New Business Opportunities`, `Opportunity-Renewal Opportunities`, `Opportunity-ALM - Renewal Opportunities`, `Opportunity-Cancellation`
- **Compact layouts (2):** `New_Awesome_Companct_Layout`, `Renewals_Compact_Layout`
- **Field:** `Opportunity.Sales_Development_Representative__c`
- **Record types (4):** `New_Business`, `Renewals`, `Cancellations`, `Opportunity_Readonly`
- **Flow (analysis only):** `Create_Opportunity_Contacts`

⚠️ **`Opportunity-CPQ Opportunity Layout`** is listed by the org but **could not be retrieved** ("Entity of type 'Layout' … cannot be found") — almost certainly a managed-package (Salesforce CPQ / SBQQ) layout. It is **excluded** from these changes; handle separately if CPQ opportunities need the SDR field surfaced.

---

## Key findings from the retrieved metadata

1. **The SDR field is on NONE of the 5 page layouts** — it is *absent*, not buried. So "surface on the main layout" = **add** it; "make read-only on the layout" = add it **as a read-only item** (there is nothing to flip).
2. **Neither compact layout includes the SDR field** → it does not appear in the Lightning highlights panel today.
3. **Native team add button already hidden on most layouts.** The `RelatedOpportunitySalesTeam` related list is on all 5 layouts (showing MemberName, OppAccessLevel, TeamMemberRole), but `AddOppTeamMember` (+ other team buttons) is **excluded on 4 of 5**:

   | Layout | Native "Add Team Member" button |
   |---|---|
   | New Business Opportunities | excluded (hidden) |
   | ALM - New Business Opportunities | excluded (hidden) |
   | Renewal Opportunities | excluded (hidden) |
   | ALM - Renewal Opportunities | excluded (hidden) |
   | **Cancellation** | **NOT excluded (native add still available)** |

   → They have **already partially standardised on the widget** by hiding the native add button — except on the Cancellation layout.
4. **Field help text is stale/misleading:** the field description and inline help say it is populated *"from the Opportunity Contact Role where Role = 'Sales Development Representative'"* and "Do not manually edit." The actual source of truth is the **OpportunityTeamMember** (team), not a Contact Role. The "do not manually edit" intent supports read-only, but the "Contact Role" wording should be corrected.

---

## Step 2 — Planned changes (prepared, NOT yet deployed)

**(b) Surface the field** — add `Sales_Development_Representative__c`:
- to **both compact layouts** (highlights panel), appended after the existing fields.
- to the **"Opportunity Information" section** of each of the 5 page layouts, immediately after `OwnerId`.

**(a) Read-only** — set the page-layout item `<behavior>Readonly</behavior>` (vs `Edit`). Exact insert modelled on the existing structure:
```xml
<layoutItems>
    <behavior>Readonly</behavior>   <!-- or Edit, depending on sequencing decision -->
    <field>Sales_Development_Representative__c</field>
</layoutItems>
```

**FLS recommendation (Step 2a):** *Do not set FLS read-only yet.* Page-layout read-only is enough to stop hand-edits in the UI. FLS read-only is cleaner long-term and the audit confirms the stamping flows run `SystemModeWithoutSharing` (so they can still write with user FLS = read-only) — but FLS read-only **also blocks Data Loader/API edits by non-system users**, which is undesirable while the auto-stamp flow is not yet live and manual correction may still be needed. Recommend: layout read-only now; revisit FLS read-only **after** `OpportuintyTeam_AfterSave` is active. (Will only apply FLS if you approve.)

---

## Step 3 — Decisions to analyse (recommendations; awaiting sign-off)

### WHICH DOOR — widget vs native related list

**What the widget (`Create_Opportunity_Contacts`) does beyond a plain add** (so we know what's lost if retired):
- Enforces **one SDR** and **one CED** per opportunity (blocks a second).
- **Blocks adding team members to Closed Won** opps for non-System-Admins.
- Aggregates **CS Contact** members into `CS_Contact__c`; stamps CED and SDR lookups.
- **Clears** the SDR/CED lookup when the matching member is removed (its Remove path).
- Writes **Flow Log** records; nicer guided UX (and a confetti success screen).

**Trade-off:**
- *Keep widget canonical* → retains one-SDR/one-CED validation, Closed-Won guard, field clearing on removal, logging — but is custom code to maintain, and its lookup writes become partly redundant once the auto-stamp flow is live.
- *Standardise on native related list* → fewer custom moving parts, but you **lose** all of the above guards unless re-implemented elsewhere.

**Recommendation:** **Keep the widget as the canonical "add SDR" door**, and keep the native related list **visible but read-only** (add button already hidden on 4/5 layouts — also hide it on **Cancellation** for consistency). Rationale: the widget's one-SDR/Closed-Won guards are real value the related list can't provide; once the auto-stamp flow maintains the field, the related list still works for viewing the team. (If you prefer the opposite direction, the one-SDR rule below must be enforced elsewhere first.)

### ONE-SDR rule — enforce on all channels?

The widget blocks a 2nd SDR, but the related list, Data Loader, API, and the renewal copy flow do not (prod has 6 two-SDR opps; this sandbox should be checked similarly). A **validation rule alone cannot** enforce this — OpportunityTeamMember has no roll-up to Opportunity (not master-detail), so you can't count sibling SDR members in a VR formula.

**Recommendation (if one-SDR is a real rule):** enforce with a **before-save record-triggered flow (or Apex trigger) on OpportunityTeamMember** that, on insert/update to role = 'Sales Development Representative', queries existing SDR members on the same opp and throws a validation error if one already exists. This covers **all channels**. If two SDRs are sometimes valid, then the single lookup should display a **defined pick** (e.g. most-recently-created SDR) and we should document that the field is "primary SDR," not "the SDR." **Recommend building the one-SDR enforcement** — but per instructions, **not building it yet**.

---

## Step 4/5 — Deploy & verify (PENDING decision)

Will run only against KJDEV, after your go-ahead, and re-confirm the org in the deploy output:
```
sf project deploy start -o KJDEV --dry-run -d <paths>     # validate
sf project deploy start -o KJDEV -d <paths>               # deploy
```
Verify: open an Opportunity as a standard sales user → field shows in highlights panel and (if read-only chosen) is non-editable; add/change an SDR team member → confirm behaviour; diff each layout against `backup/.../source-original/` to confirm no fields were lost.

---

## PRODUCTION DEPLOYMENT PLAN (described only — NOT executed)

**Pre-req / ordering:** Deploy these UX changes to production **only after** `OpportuintyTeam_AfterSave` (auto-stamp) is **Active in production** — otherwise read-only strands SDRs added via related list/renewals. Sequence: (1) auto-stamp flow live in prod → (2) backfill confirmed (already done) → (3) this layout/compact-layout change → (4) optional FLS read-only → (5) optional one-SDR enforcement.

**Backup (prod) before deploy:**
```
sf org login web -r https://login.salesforce.com -a LBR_PROD
sf org display -o LBR_PROD          # CONFIRM username kamyar.jannati@lbresearch.com, Org Id 00D6g0000081IOgEAM
sf project retrieve start -o LBR_PROD -x backup/sdr-ux-2026-05-30/package.xml \
   --target-metadata-dir backup/PROD-sdr-ux-<date>/metadata-zip
```

**Validate-only (no changes committed):**
```
sf project deploy start -o LBR_PROD --dry-run \
   -d "force-app/main/default/layouts" \
   -d "force-app/main/default/objects/Opportunity/compactLayouts"
# (add the field dir only if FLS/help-text changes are included)
```

**Deploy:**
```
sf project deploy start -o LBR_PROD \
   -d "force-app/main/default/layouts" \
   -d "force-app/main/default/objects/Opportunity/compactLayouts"
# Re-confirm the "Target Org" line in output reads kamyar.jannati@lbresearch.com (prod) BEFORE confirming.
```

**Rollback plan:**
- Redeploy the pristine originals from the prod backup zip (or `backup/sdr-ux-2026-05-30/source-original/` if identical to prod): `sf project deploy start -o LBR_PROD -d <restored originals>`.
- Layout/compact-layout changes are additive (one field + behavior); rollback = redeploy prior layout XML. No data is touched, so no data rollback needed.

**Prod-specific risks:**
- **CPQ layout** (`Opportunity-CPQ Opportunity Layout`) is not in scope and won't get the field — CPQ opps won't show it unless handled separately.
- **Cancellation layout** still exposes the native add button — inconsistent door unless also hidden in prod.
- **FLS read-only** would block legitimate Data Loader/API corrections by non-system integration users — verify no integration writes this field as a non-system user before enabling.
- Prod has **6 multi-SDR opportunities** — surfacing a single lookup there may misrepresent the team until the one-SDR rule/clean-up is applied.
- Layout deploys overwrite the **entire** layout — ensure the source layouts are freshly retrieved from prod (not the sandbox copies) before deploying, since sandbox and prod layouts may differ.

---

## Commands/queries run (all read-only; against KJDEV unless noted)
- `sf org display -o KJDEV` (+ `--json`) — org confirmation
- `sf data query -o KJDEV -t -q "SELECT ... FROM Flow WHERE Definition.DeveloperName='OpportuintyTeam_AfterSave'"` — dependency check
- `sf data query -o KJDEV -t -q "... Flow ... IN ('Create_Opportunity_Contacts','Opportunity_Sync_Opportunity_Team','OpportunityTeam_Delete') AND Status='Active'"` — related flows
- `sf org list metadata -o KJDEV -m Layout|CompactLayout|RecordType` — inventory
- `sf project retrieve start -o KJDEV -x backup/sdr-ux-2026-05-30/package.xml [--target-metadata-dir ...]` — backup + source
- Local inspection of retrieved layout/compactLayout/field XML.
