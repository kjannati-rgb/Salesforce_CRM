# Attorney-Field Consolidation — PRODUCTION Runbook

**Target org:** `LBR_PROD` — `https://lawbusinessresearch.my.salesforce.com`
**Prepared:** 2026-06-19 (read-only recon; no prod writes performed during prep)
**Validated in:** KJDEV (full cycle incl. delete) and FULLUAT (14,064-record migration at scale incl. delete)
**Companion docs:** [Phase 1 audit](ClaudeCode_AttorneyField_Consolidation_Phase1_Audit.md), [Phase 2 plan](ClaudeCode_AttorneyField_Consolidation_Phase2_Plan.md)

- **SURVIVOR (keep):** `Account.Number_of_Attorneys__c` (`00NTm000002XohdMAC`)
- **RETIRE (delete):** `Account.of_Attorneys__c` (`00NPx00000ACARFMA5`)

---

## Prod recon — confirmed facts (2026-06-19, read-only)

| Item | Finding |
|---|---|
| Fields present | All 4 exist in prod incl. `ALM_Industry_Category_Code__c` (FULLUAT lacked it) |
| Metadata refs (dep graph) | 2 formulas (`Industry_Category__c`, `ALM_Industry_Category_Code__c`) + 2 layouts (`Firm Layout`, `Office Layout - Data Team`) |
| **Delete blockers (dry-run destructive validate)** | **Only the 2 formula fields.** No FlexiPages block (prod record pages already use the survivor). Layouts auto-detach on delete. |
| CPQ rules / quote templates | Verified clean earlier (0 attorney-field refs across ~15.3k rule + ~10k template records) |
| Data scope | **As of 2026-06-19 the ALM team re-synced both fields**: 17,927 accounts populated, **both fields identical, 0 conflicts, 0 one-sided gaps** → **migration is a no-op**. (Was 29,684/29,779 earlier; ALM full refresh dropped ~12k stale records — confirmed intentional.) |
| FLS | **35 parents** (2 perm sets + 33 profiles) have edit on retire but not survivor — incl. **System Administrator** |

> ⚠️ **Two dependency-graph blind spots confirmed this project** (both invisible to "Where is this used?" too): **CPQ rule/template data records** and **FlexiPage field references**. Prod is clean on both, but the dry-run destructive validate (Step 5 pre-check) is the safety net that proves it.

---

## Pre-flight sign-offs & manual checks (before any write)

1. ~~**Conflict tie-break**~~ **RESOLVED** — ALM team re-synced both fields in prod (2026-06-19); 0 conflicts remain, so no tie-break decision needed.
2. **Go-forward owner:** ALM data team commits to maintaining `Number_of_Attorneys__c`; **repoint the ALM refresh/load job to write the survivor** (it currently writes `of_Attorneys__c`, which is being retired).
3. **Reports/dashboards:** run Setup → Object Manager → Account → Fields → **of_Attorneys__c → "Where is this used?"** (covers reports, which the dep graph doesn't fully). Repoint/flag any report filter/column. *(6,424 reports — too many to grep; this Setup tool is the check.)*
4. **Lead conversion map:** Setup → Object Manager → **Lead → Map Lead Fields** — confirm `ALM_of_Attorneys__c` does **not** map to `Account.of_Attorneys__c`; if it does, remap to `Number_of_Attorneys__c`.
5. **Data Cloud:** confirm no data stream/DLO ingests `of_Attorneys__c`; if so, remap to survivor.
6. **Soak length** before deletion (suggest 2–4 weeks).

---

## Execution order (behavior-neutral; data migrates BEFORE formula repoint)

### Step 0 — Branch + baseline retrieve from PROD
```bash
git switch -c attorney-consolidation-prod
sf project retrieve start --target-org LBR_PROD \
  -m "CustomField:Account.of_Attorneys__c" \
  -m "CustomField:Account.Number_of_Attorneys__c" \
  -m "CustomField:Account.Industry_Category__c" \
  -m "CustomField:Account.ALM_Industry_Category_Code__c" \
  -m "Layout:Account-Firm Layout" \
  -m "Layout:Account-Office Layout - Data Team"
git add -A && git commit -m "Baseline: attorney consolidation from LBR_PROD (pre-edit)"
```

### Step 1 — FLS so the migration user can write the survivor
The migration writes `Number_of_Attorneys__c`, but **System Administrator lacks survivor edit**. Simplest: a dedicated perm set assigned to the migration user.
```bash
# Create permission set "Attorney_Migration" granting Read+Edit on Account.Number_of_Attorneys__c,
# assign to the running user, OR run the migration via Batch Apex (system mode, below) which needs no FLS.
```
Then do the **go-forward FLS parity** (survivor edit on the parents that had retire edit). Recommended scope: the **2 perm sets** (`ALM_fields_data_team`, `Additional_Account_Permission_for_ALM_CS_team`) + the human Sales/Data-Management profiles. Full list of 35 parents from recon; integration/read-only profiles can be skipped (they don't edit attorney counts). *(Deploy perm sets/profiles retrieved natively from PROD — do not push sandbox copies.)*

### Step 2 — Backup (rollback source)
```bash
sf data query -q "SELECT Id, of_Attorneys__c, Number_of_Attorneys__c FROM Account WHERE of_Attorneys__c != null" \
  --target-org LBR_PROD --result-format csv > attorney_PROD_backup_YYYYMMDD.csv   # ~29,684 rows
```

### Step 3 — Data migration — **NO-OP (already done by ALM refresh 2026-06-19)**
The two fields are already identical on all 17,927 populated accounts (0 conflicts, 0 one-sided gaps), so no migration/Data-Loader/batch run is needed, and Step 1 FLS is no longer required *for migration* (only for go-forward editing).
**Just verify before proceeding** (cheap, read-only):
```bash
sf data query -q "SELECT Id, of_Attorneys__c, Number_of_Attorneys__c FROM Account WHERE of_Attorneys__c != null OR Number_of_Attorneys__c != null" --target-org LBR_PROD --json
# compute client-side: expect 0 where the two differ, 0 where only one is populated
```
Because the fields are equal everywhere, the Step 4 formula repoint is inherently behavior-neutral.
*(`AttorneyCountMigrationBatch` remains in the branch as a safety tool but is not needed for prod.)*

### Step 4 — Repoint formulas + swap layouts (deploy)
Natively edit the PROD-retrieved files: in `Industry_Category__c` and `ALM_Industry_Category_Code__c`, swap every `of_Attorneys__c` → `Number_of_Attorneys__c`; swap the field item on both layouts.
```bash
sf project deploy start --target-org LBR_PROD --dry-run \
  -m "CustomField:Account.Industry_Category__c" -m "CustomField:Account.ALM_Industry_Category_Code__c" \
  -m "Layout:Account-Firm Layout" -m "Layout:Account-Office Layout - Data Team"
# then deploy without --dry-run
```

### Step 5 — Re-audit (gate before deprecate/delete)
```bash
sf data query --use-tooling-api -q "SELECT MetadataComponentName, MetadataComponentType FROM MetadataComponentDependency WHERE RefMetadataComponentId='00NPx00000ACARFMA5'" --target-org LBR_PROD   # expect 0
# Authoritative blocker check (dry-run destructive — NO changes): expect Succeeded
sf project deploy start --manifest package.xml --post-destructive-changes destructiveChangesPost.xml --target-org LBR_PROD --dry-run
```

### Step 6 — Deprecate (non-destructive; start soak)
Natively edit PROD `of_Attorneys__c`: relabel `ALM # of Attorneys (DEPRECATED)` (≤40 chars) + inlineHelpText → survivor; set FLS read-only (Edit=false, Read kept) on the parents that had edit. Deploy. **Soak 2–4 weeks.**

### Step 7 — DELETE (destructive — separate explicit confirmation)
```xml
<!-- destructiveChangesPost.xml -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types><members>Account.of_Attorneys__c</members><name>CustomField</name></types>
</Package>
```
```bash
sf project deploy start --manifest package.xml --post-destructive-changes destructiveChangesPost.xml --target-org LBR_PROD --dry-run   # expect Succeeded
# then without --dry-run  (NEVER without explicit go-ahead for this exact step)
```

---

## Rollback

| Step | Rollback | Window |
|---|---|---|
| 1 FLS | redeploy baseline perm sets/profiles | anytime |
| 3 Data | Data Loader update from `attorney_PROD_backup_*.csv` (Id, Number_of_Attorneys__c) | anytime pre-Step 7 |
| 4 Formulas/layouts | redeploy Step-0 baseline | anytime |
| 6 Deprecate | redeploy baseline label/FLS | anytime |
| 7 Delete | Setup → Deleted Fields → **Undelete** (restores field + data) | **15 days**, then recreate + reload backup |

---

## Notes carried from sandbox cycles
- KJDEV: full cycle done incl. delete (deploys `…RLvLVKA1`, `…RLwENKA1`, `…RLx7CKAT`).
- FULLUAT: 14,064-record migration (0 errors) + repoint + deprecate + **delete** done; required repointing 2 FlexiPages first (older clone) — prod does **not** have that issue.
- `of_Attorneys__c` is human-maintained by the ALM/Law.com data team (no integration writes it) — retirement is safe once stewardship is redirected (pre-flight #2).
