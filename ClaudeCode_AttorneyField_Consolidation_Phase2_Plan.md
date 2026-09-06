# Account Attorney-Count Field Consolidation — Phase 2: Remediation & Rollback Plan

**Date:** 2026-06-19
**Status:** PLAN ONLY — no org writes. Execution is Phase 3, gated step-by-step by explicit approval.
**Companion:** see [Phase 1 audit](ClaudeCode_AttorneyField_Consolidation_Phase1_Audit.md) for evidence behind every reference below.

- **SURVIVOR (keep):** `Account.Number_of_Attorneys__c` — Number(18,0), Id `00NTm000002XohdMAC`
- **RETIRE (remove):** `Account.of_Attorneys__c` — Number(18,0), Id `00NPx00000ACARFMA5`
- **Do not touch:** `Account.Total_US_Attorneys__c`, `Account.Total_Non_US_Attorneys__c`

### Conflict tie-break (the one business decision baked into this plan)
**Default = RETIRE wins.** Where both fields are populated but differ (622 records), `Number_of_Attorneys__c` is overwritten with `of_Attorneys__c`. Rationale: the retire field is the ALM-maintained source, and this keeps the formula repoint (Step 4) **behavior-neutral** because `Industry_Category__c` / `ALM_Industry_Category_Code__c` read the retire value *today*. **Requires ALM data-team sign-off** (it changes 622 survivor values). If they prefer SURVIVOR-wins, Step 3 shrinks to the 109 blanks only and Step 4 becomes behavior-*changing* for 622 accounts — call that out to stakeholders.

---

## Guiding principles

1. **Nothing destructive without explicit, separate confirmation.** Field deletion (Step 8) is isolated from everything else.
2. **Sandbox → Full UAT → Production.** Build/validate metadata in **KJDEV**; rehearse the **data migration** in **FULLUAT** (prod-like data) before PROD.
3. **Behavior-neutral ordering in PROD:** migrate data **before** repointing formulas, so the formulas' output doesn't change when they flip to the survivor.
4. **Back up before every change** — metadata via git baseline; data via a pre-migration CSV export (which doubles as the rollback source).
5. **Re-prove zero references** (Phase 1 audit re-run) before any deprecation/deletion.

---

## Environment & sequencing overview

| # | Step | Type | KJDEV | FULLUAT | PROD | Reversible? |
|---|------|------|:---:|:---:|:---:|:---:|
| 0 | Branch + baseline retrieve | git/metadata | ✅ | — | — | n/a |
| 1 | FLS parity for survivor | metadata | ✅ | ✅ | ✅ | yes (redeploy) |
| 2 | Pre-migration data backup (export) | data | — | ✅ | ✅ | n/a (is the backup) |
| 3 | Data migration: survivor ⃪ retire | data | n/a (0 records) | ✅ | ✅ | yes (reload backup) |
| 4 | Repoint 2 formula fields → survivor | metadata | ✅ | ✅ | ✅ | yes (redeploy) |
| 5 | Swap field on 2 layouts | metadata | ✅ | ✅ | ✅ | yes (redeploy) |
| 6 | Re-run Phase 1 audit (prove 0 refs) | verify | ✅ | ✅ | ✅ | n/a |
| 7 | Redirect stewardship + Data Cloud stream | config/people | — | — | ✅ | yes |
| 8 | Deprecate `of_Attorneys__c` | metadata | ✅ | ✅ | ✅ | yes (redeploy) |
| 9 | **DELETE** `of_Attorneys__c` (separate sign-off) | destructive | ✅ | ✅ | ✅ | 15-day undelete window |

> **Critical PROD ordering:** Step 1 → Step 2 → **Step 3 (data) must finish before Step 4 (formula deploy)** → Step 5 → Step 6 → Step 7 → soak → Step 8 → soak → Step 9.
> In **KJDEV** there's no data, so Steps 2/3 are skipped; we instead create a few synthetic test Accounts (see Step 4 validation) to prove the repoint is output-neutral.

---

## Step 0 — Branch + baseline retrieve (KJDEV)

**Action.** New git branch; retrieve the exact components we will touch so we have a pristine pre-edit baseline to diff against and to redeploy for rollback.

```bash
git switch -c attorney-field-consolidation
# clear dead proxy vars first (per session)
sf project retrieve start --target-org KJDEV \
  -m "CustomField:Account.of_Attorneys__c" \
  -m "CustomField:Account.Number_of_Attorneys__c" \
  -m "CustomField:Account.Industry_Category__c" \
  -m "CustomField:Account.ALM_Industry_Category_Code__c" \
  -m "Layout:Account-Firm Layout" \
  -m "Layout:Account-Office Layout - Data Team" \
  -m "PermissionSet:ALM fields - Data team" \
  -m "PermissionSet:Additional Account Permission for ALM CS team"
git add -A && git commit -m "Baseline: attorney-field consolidation (pre-edit)"
```
**Rollback.** `git revert`/redeploy this baseline commit restores any metadata component.

---

## Step 1 — FLS parity for the survivor (metadata)

**Why.** After cutover, anyone who could read/edit `of_Attorneys__c` must retain that on `Number_of_Attorneys__c`. Phase 1 found the survivor lacks parity in two permission sets. (Profiles already had parity in the sandbox; **regenerate the exact delta from the PROD `FieldPermissions` snapshot** before deploying — see query below — because prod may differ.)

**Gap to close (from Phase 1, confirm in prod):**

| Permission set | retire | survivor today | change |
|---|---|---|---|
| `ALM fields - Data team` | R/W | **R only** | add **Edit** to survivor |
| `Additional Account Permission for ALM CS team` | R/W | **absent** | add survivor **R/W** |

**Generate the authoritative delta (read-only):**
```sql
-- run against the target org; any row where retire has access the survivor lacks = a gap to add
SELECT Parent.Label, Parent.IsOwnedByProfile, Field, PermissionsRead, PermissionsEdit
FROM FieldPermissions
WHERE Field IN ('Account.of_Attorneys__c','Account.Number_of_Attorneys__c')
ORDER BY Parent.Label, Field
```

**How.** Edit the retrieved `permissionset-meta.xml` (and any profile that shows a gap) to add the survivor `fieldPermissions` entry, deploy.

**Validation.** Re-run the FLS query; survivor access ≥ retire access for every parent.
**Rollback.** Redeploy Step 0 baseline of the permission sets/profiles.

---

## Step 2 — Pre-migration data backup (PROD/FULLUAT only)

**Why.** This export is both an audit artifact and the **rollback source** for Step 3.

```sql
-- export to CSV, keep with timestamp; ~29,684 rows
SELECT Id, of_Attorneys__c, Number_of_Attorneys__c
FROM Account
WHERE of_Attorneys__c != null
```
Store as `attorney_backup_PROD_YYYYMMDD.csv`. Verify row count ≈ 29,684 (prod, 2026-06-19).

---

## Step 3 — Data migration: `Number_of_Attorneys__c := of_Attorneys__c` (PROD/FULLUAT only)

**Scope (prod, 2026-06-19):** 738,825 Accounts; **731 records change** = 109 survivor-blank + 622 conflicts (RETIRE-wins). The other 28,953 already match; 204 survivor-only are untouched. *(SURVIVOR-wins variant → only the 109 blanks change.)*

**Recommended method — Data Loader (no code, fully auditable):**
1. From the Step 2 export, compute the update set in a spreadsheet: rows where `Number_of_Attorneys__c <> of_Attorneys__c` (incl. blank survivor) → set new `Number_of_Attorneys__c = of_Attorneys__c`. Expect ~731 rows.
2. Data Loader **Update** with `Id, Number_of_Attorneys__c`.
3. **Grain note:** the set naturally includes both office and Firm (Ultimate Account) records, so the CPQ quote formula (`Quote.Number_of_Attorneys__c → Account.Ultimate_Account__r.Number_of_Attorneys__c`) is satisfied (Phase 1 §6b).

**Coded alternative — Batch Apex** (200 scope) if trigger cascades/limits are a concern; compare per-record and update only where different. Avoid a single anonymous-Apex pass over all 29,684 (sync heap risk).

**Side-effects check.** Updating attorney count does **not** fire the `Account Update Industry Category` before-save flow (it triggers only on `Industry_Data_Provider__c` / `Industry_Category_Override__c` / `Industry_ALM__c` changes). Other Account triggers will fire on 731 updates — small; run in a low-traffic window. Consider the org bypass (`Application_Settings__c`) only if needed.

**Validation.** Re-run the conflict query (Phase 1 method: pull both-populated set, compare client-side) → expect **0 differing, 0 survivor-blank-where-retire-populated**.
**Rollback.** Data Loader **Update** from `attorney_backup_*.csv` (`Id, Number_of_Attorneys__c` original values) restores prior survivor values exactly. Window: anytime (data is retained).

---

## Step 4 — Repoint the two formula fields → survivor (metadata)

**Why/Order.** Must run **after** Step 3 in PROD so output is unchanged. A formula referencing `of_Attorneys__c` also **blocks deletion** of the field, so this must precede Step 9.

**Edits (token-for-token swap, thresholds unchanged):**
- `Account.Industry_Category__c`: replace each `of_Attorneys__c` → `Number_of_Attorneys__c` (3 occurrences; ≥151/≥71/≥6/≤5 buckets).
- `Account.ALM_Industry_Category_Code__c`: replace each `of_Attorneys__c` → `Number_of_Attorneys__c` (≥151/≥71/≥6 buckets, incl. the `ISBLANK(...)` guard).

**Validation (KJDEV, synthetic data since org is empty):** create ~6 test Accounts spanning the thresholds (e.g. attorney counts 3, 6, 71, 151, 0/blank) with `of_Attorneys__c = Number_of_Attorneys__c` and `Industry_ALM__c = "Law Firm"`; snapshot `Industry_Category__c` + `ALM_Industry_Category_Code__c` **before** deploy, repoint, confirm **identical** after. In FULLUAT/PROD (post-migration), spot-check several of the former 622 conflicts → category unchanged.
**Rollback.** Redeploy Step 0 baseline of the two formula fields.

---

## Step 5 — Swap the field on the two layouts (metadata)

**Why.** Both layouts show `of_Attorneys__c` (editable) and **neither shows the survivor** — swap so users keep an attorney field and stop writing to the retire field.

**Edits:** in `Account-Firm Layout` and `Account-Office Layout - Data Team`, change `<field>of_Attorneys__c</field>` → `<field>Number_of_Attorneys__c</field>` (same position/`Edit` behavior).
**Validation.** Open each layout; survivor present where retire was; retire absent.
**Rollback.** Redeploy Step 0 baseline of the two layouts.

---

## Step 6 — Re-run the Phase 1 audit (prove zero remaining references)

Before any deprecation, re-confirm `of_Attorneys__c` is referenced by **nothing** except its own definition:
1. Tooling dependency graph by Id (`RefMetadataComponentId = '00NPx00000ACARFMA5'`) → expect **0**.
2. Grep retrieved Account object + layouts + the two formulas → only the field's own definition remains.
3. CPQ rules + templates re-scan in PROD (Phase 1 §6/§6b columns) → **0** (already clean).
**Gate:** do not proceed to Step 8/9 until this is clean.

---

## Step 7 — Redirect go-forward stewardship & downstream consumer (PROD config/people)

**Why.** `of_Attorneys__c` is human-maintained by the ALM/Law.com data team (Phase 1) and read by Data Cloud.
- ALM data team switches data entry to `Number_of_Attorneys__c`; any Data Loader/ETL job remapped to the survivor.
- **Lead conversion:** confirm in **Setup → Object Manager → Lead → Map Lead Fields** whether `ALM_of_Attorneys__c` maps to `Account.of_Attorneys__c`; if so, remap to `Number_of_Attorneys__c`.
- **Data Cloud:** if a data stream ingests `of_Attorneys__c`, remap the stream/DLO mapping to the survivor.
**Rollback.** Revert mapping/config; resume old field entry (only meaningful before Step 9).

---

## Step 8 — Deprecate `of_Attorneys__c` (metadata, non-destructive)

**Why.** Stop new writes and signal retirement while keeping data for a soak period (safety net before deletion).
- Remove from all layouts (done in Step 5).
- Relabel → `ALM # of Attorneys (DEPRECATED — use Number of Attorneys)`; add inline help pointing to the survivor.
- Tighten FLS to **read-only** (remove Edit everywhere) so nothing writes it during the soak.
**Soak:** agree a window (e.g. 2–4 weeks) to confirm no process/report/user breaks.
**Rollback.** Redeploy baseline label/FLS; re-add to layouts.

---

## Step 9 — DELETE `of_Attorneys__c` (destructive — separate explicit confirmation)

**Preconditions:** Step 6 clean, Step 8 soak elapsed with no issues, reports/lead-map manual checks done, stakeholder + data-team go-ahead.

**How:** destructive deploy (`destructiveChangesPost.xml` with `CustomField` = `Account.of_Attorneys__c`, empty `package.xml`), KJDEV → FULLUAT → PROD.
```xml
<!-- destructiveChangesPost.xml -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types><members>Account.of_Attorneys__c</members><name>CustomField</name></types>
</Package>
```
**Never run a destructive deploy without an explicit, separate "yes" for this exact step.**

**Rollback / recovery.**
- **≤15 days:** Setup → Object Manager → Account → Fields → *Deleted Fields* → **Undelete** (restores field + data). API name stays reserved during this window.
- **After permanent erase:** field must be recreated (API name was locked); restore values from `attorney_backup_*.csv`. Treat post-erase as effectively irreversible — hence the soak.

---

## Rollback master table

| Step | Rollback action | Window |
|---|---|---|
| 1 FLS | Redeploy baseline permission sets/profiles | anytime |
| 3 Data migration | Data Loader update from `attorney_backup_*.csv` | anytime (pre-Step 9) |
| 4 Formulas | Redeploy baseline formula fields | anytime |
| 5 Layouts | Redeploy baseline layouts | anytime |
| 7 Stewardship/Data Cloud | Revert mappings, resume old entry | before Step 9 |
| 8 Deprecate | Redeploy baseline label/FLS, re-add to layouts | anytime |
| 9 Delete | Undelete (≤15 days) → else recreate + reload backup | 15 days, then hard |

---

## Residual manual checks (carry from Phase 1)

- **Reports/dashboards (6,424):** run the field's Setup **"Where is this used?"** in PROD (covers reports) — too many to grep; dependency graph already clean. Do before Step 9.
- **Lead conversion map:** Step 7.

## Open decisions for sign-off

1. **Conflict tie-break:** confirm **RETIRE-wins** (default, behavior-neutral) vs SURVIVOR-wins. *(Needs ALM data-team OK — changes 622 values.)*
2. **Go-forward owner:** ALM data team commits to maintaining `Number_of_Attorneys__c`.
3. **Soak length** before deletion (suggest 2–4 weeks).
4. **Deprecate-only vs delete:** OK to plan toward deletion, or stop at deprecation indefinitely?

On your approval of these, Phase 3 begins at **Step 0** in KJDEV — diffs shown, nothing deployed without your go-ahead.
