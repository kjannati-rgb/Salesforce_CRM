# ChurnZero Account-Team update — Production runbook

**Date prepared:** 2026-05-29
**Org:** Production (`kamyar.jannati@lbresearch.com`)
**Source sheet:** `SF initial client list - Chris list - 1Apr26 - Account Teams and Masters - 6May26 v3.xlsx` (Sheet1, 10,608 rows)
**Request:** Chris Riley email, 29 May 2026 — replace Laura Murr with the 3 Tech Touch users in Account Teams, load Law.com Service Levels, rename fields/role.

> All record counts below were taken from production on 2026-05-29. Re-run the verification queries before executing if more than a few days have passed.

---

## Files in this folder

| File | Operation | Object | Rows | Match on |
|------|-----------|--------|-----:|----------|
| `01_delete_laura_murr_ATM.csv` | **Delete** | AccountTeamMember | 4,014 | `Id` |
| `02_insert_techtouch_ATM.csv` | **Insert** | AccountTeamMember | 4,234 | n/a |
| `03_update_lawcom_service_level.csv` | **Update** | Account | 1,675 | `Id` |

Supporting (not for loading): `_laura_all.csv` (Laura's 4,014 records with Account + role — keep as the rollback/audit reference), `_distinct_accounts.txt`.

---

## Recommended order of operations

Metadata renames are independent of the data loads (we kept the API names, so nothing depends on the labels). Suggested sequence:

1. **Backups / exports** (see Pre-flight).
2. **Delete** Laura Murr's 4,014 Account Team Members — `01_…`.
3. **Insert** the 4,234 Tech Touch Account Team Members — `02_…`.
4. **Update** the 1,675 Law.com Service Levels — `03_…`.
5. **Field label renames** (Setup) — items A & B below.
6. **Verify** (post-checks) and notify ChurnZero owner to confirm the sync still maps correctly.

---

## Pre-flight (do first)

1. **Export current state for rollback:**
   - All of Laura Murr's ATM rows (full fields) — already captured in `_laura_all.csv`, but take a fresh Data Loader export of `AccountTeamMember WHERE UserId='005Tm000001zhCLIAY'` with **all** columns (AccountId, UserId, TeamMemberRole, AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel, ContactAccessLevel) so the deletes can be re-inserted if needed.
   - Export `Id, ALM_Service_Level__c` for the 1,675 accounts in `03_…` **before** updating, so the field can be reverted.
2. **Confirm the 3 Tech Touch users are active** (they were on 2026-05-29):
   - `005Px00000BnqaDIAR` Tech Touch CS E&I · `005Px00000Bnl4HIAR` Tech Touch CS PI · `005Px00000Bnj46IAB` Tech Touch CS Law.com
3. Use **Data Loader** (or Bulk API). Enable the **Bulk API** for the delete/insert (4k rows each). Keep "Insert null values" **OFF**.

---

## Step 2 — Delete Laura Murr's Account Team Members

- **File:** `01_delete_laura_murr_ATM.csv` (column `Id`, 4,014 rows)
- Data Loader → **Delete** → object **Account Team Member (AccountTeamMember)** → map `Id`.
- Expected: 4,014 success. This removes **all** her team memberships (PI CSM 1,927 / E&I CSM 1,147 / Law.com CSM 939 / + 1 misc role — all confirmed by the user as in-scope).
- Any row error = that ATM was already deleted; safe to ignore.

## Step 3 — Insert Tech Touch Account Team Members

- **File:** `02_insert_techtouch_ATM.csv` (4,234 rows)
- Columns: `AccountId, UserId, TeamMemberRole, AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel, ContactAccessLevel`
- Access levels mirror the existing CSM rows: **Account=Edit, Opportunity=Read, Case=None, Contact=Edit**.
- Breakdown: E&I CSM 1,347 · PI CSM 1,929 · Law.com CSM 958.
- Built strictly from the sheet: wherever col P/V/S = "Tech Touch CS E&I/PI/Law.com", deduped by (Account, User, Role). The 3 users currently have **0** team rows, so no duplicates.
- Row errors to expect/triage: account deleted/merged since 6-May (drop it), or a uniqueness clash if the same user+account already exists.

## Step 4 — Update Law.com Service Level

- **File:** `03_update_lawcom_service_level.csv` (1,675 rows)
- Object **Account**, **Update**, map `Id` and `ALM_Service_Level__c`.
- Values already normalised to the picklist (`Tech Touch` 1,097 · `High Touch` 226 · `Low Touch` 177 · `Mid Touch` 175). The sheet's hyphenated forms (`Tech-Touch` etc.) were mapped to the space form the picklist uses.
- **Only accounts with a value in column R are touched.** The 8,933 `N/A`/`#N/A` rows are intentionally **left untouched** (we are not blanking existing values). Each Ultimate Account had a single, non-conflicting Law.com level across its division rows (0 conflicts found).
- **Note on field name:** we are loading into `ALM_Service_Level__c` (unchanged API name). The label rename below is cosmetic and does not affect this load.

---

## Metadata changes (Setup)

Decision: **rename labels only, keep API names** (so ChurnZero, flows, reports keep working).

**A. ALM Service Level → Law.com Service Level**
- Setup → Object Manager → **Account** → Fields & Relationships → `ALM_Service_Level__c` → Edit → **Field Label** = `Law.com Service Level`. Leave **Field Name** (`ALM_Service_Level__c`) unchanged. Update the related tab/help text if desired.

**B. SPG & Lexology PRO Service Level → PI Service Level**
- Same path → `SPG_Lexology_PRO_Service_Level__c` → **Field Label** = `PI Service Level`. Leave API name unchanged.

> After a label change, check any **Reports/List Views** that show the column header text — the column keeps working but the displayed label updates automatically; saved report names that hard-code "ALM" in their title won't change on their own.

**C. "ALM CSM" Team Role → "Law.com CSM"**
- **Already done.** Production Account Team roles in use are already `PI CSM`, `E&I CSM`, **`Law.com CSM`** (1,518 records) — there is **no "ALM CSM"** role in use. Just confirm in Setup → Feature Settings → Sales → Account Teams → **Team Roles** that the picklist no longer lists "ALM CSM". No action expected.

---

## Post-checks (after loading)

Run in the production connector / Developer Console:

```sql
-- Laura Murr should now have 0
SELECT COUNT(Id) FROM AccountTeamMember WHERE UserId='005Tm000001zhCLIAY'

-- Tech Touch users should total ~4,234 (E&I 1347 / PI 1929 / Law.com 958)
SELECT UserId, TeamMemberRole, COUNT(Id) c FROM AccountTeamMember
WHERE UserId IN ('005Px00000BnqaDIAR','005Px00000Bnl4HIAR','005Px00000Bnj46IAB')
GROUP BY UserId, TeamMemberRole

-- Law.com service level populated on ~1,675 accounts
SELECT ALM_Service_Level__c, COUNT(Id) c FROM Account
WHERE Id IN (:the 1,675 ids) GROUP BY ALM_Service_Level__c
```

Then ask the **ChurnZero integration owner** to confirm the next sync picks up the new CSM owners correctly.

---

## Rollback

- **Inserts:** delete the rows created in Step 3 (Data Loader keeps a success file with the new ATM Ids — delete by those Ids).
- **Deletes:** re-insert from the pre-flight export of Laura's rows (or `_laura_all.csv` + access-level columns).
- **Service level:** re-update from the pre-update export of `Id, ALM_Service_Level__c`.
- **Labels:** revert the Field Label text in Setup.

---

## Notes / caveats

- The Salesforce MCP connector returned an inconsistent `TeamMemberRole` for one of Laura's records across two reads (aggregate said "CS Contact", detail said "PI CSM"). It does **not** affect the delete (we delete all 4,014 by `Id`). Counts by role are therefore approximate by ±1 between roles; the total (4,014) is exact.
- AccountIds were spot-validated (200-ID spread sample = 100% present). Full validation is the Data Loader error log.
- This was prepared as load files because the volume (~9,900 DML ops) and the lack of a bulk/delete path through the live connector make Data Loader the safe, standard route.
