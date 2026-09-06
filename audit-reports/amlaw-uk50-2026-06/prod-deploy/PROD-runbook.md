# Am Law UK 50 Whitespace — PROD Deployment Runbook

**STATUS: prepared, NOT executed. Every PROD step below needs the user's explicit go-ahead.**
Org alias: `LBR_PROD`. Source built + validated in KJDEV.

---

## 0. Two things needed from the user before deploy
1. **PROD running user** for the dashboard — a fixed user with org-wide visibility (Rev Ops/admin). The dashboard currently carries my KJDEV user `kamyar.jannati@lbresearch.com.kjdev` in `<runningUser>` and `<owner>`; both MUST be swapped to the PROD user or the deploy fails / runs as the wrong identity.
2. **FLS audience** — which profiles/perm sets (or the Revenue Operations report-folder audience) should get the `Am_Law_UK_50_Whitespace_Access` perm set. (Folder sharing wasn't API-queryable — `FolderShare` INVALID_TYPE — so this is confirmed manually.)

## 1. CRITICAL caveat — the shared report type
`Custom_Opportunities_with_Products` is a large, shared report type. The copy in this repo was retrieved from **KJDEV** and may differ from PROD. Deploying it as-is could **overwrite PROD-only fields**.
**Do NOT deploy the repo copy.** Instead, at deploy time:
1. Retrieve PROD's current version:
   `sf project retrieve start -m "ReportType:Custom_Opportunities_with_Products" -o LBR_PROD --target-metadata-dir <tmp> --unzip`
2. Add ONLY this one column to PROD's copy (after the `Ultimate_Account__c.Account_tier__c` column):
   ```xml
   <columns>
       <checkedByDefault>false</checkedByDefault>
       <displayNameOverride>Firm: Am Law UK 50 Rank</displayNameOverride>
       <field>Ultimate_Account__c.Am_Law_UK_50_Rank__c</field>
       <table>Opportunity</table>
   </columns>
   ```
3. Deploy that reconciled file (not the repo copy).

The other report type (`Accounts_with_or_without_Opportunities`) is brand new — deploy the repo copy as-is.

## 2. Components to deploy (see package.xml)
- CustomField `Account.Am_Law_UK_50_Rank__c`
- PermissionSet `Am_Law_UK_50_Whitespace_Access`
- ReportType `Accounts_with_or_without_Opportunities` (new)
- ReportType `Custom_Opportunities_with_Products` (reconciled per §1)
- Report folder `Am Law UK 50 Whitespace` + 4 reports (Current, LastYear, YoY, Never-Served)
- Dashboard folder + `Am Law UK 50 Whitespace` dashboard (running user fixed per §0)

## 3. Deploy sequence (run ONLY on confirmation, per step)
**3a. Validate-only (no commit) first:**
```
sf project deploy start -o LBR_PROD -x audit-reports/amlaw-uk50-2026-06/prod-deploy/package.xml --dry-run --test-level RunLocalTests
```
(or `-d` the individual source paths). Review results before proceeding.

**3b. Field + perm set + report types** (deploy together — field+permset are transactional):
```
sf project deploy start -o LBR_PROD -m "CustomField:Account.Am_Law_UK_50_Rank__c" -m "PermissionSet:Am_Law_UK_50_Whitespace_Access" -m "ReportType:Accounts_with_or_without_Opportunities" -m "ReportType:Custom_Opportunities_with_Products"
```
**3c. Reports + dashboard** (after the report type is live, with the dashboard running user fixed):
```
sf project deploy start -o LBR_PROD -d force-app/main/default/reports/Am_Law_UK_50_Whitespace.reportFolder-meta.xml -d force-app/main/default/reports/Am_Law_UK_50_Whitespace -d force-app/main/default/dashboards/Am_Law_UK_50_Whitespace.dashboardFolder-meta.xml -d force-app/main/default/dashboards/Am_Law_UK_50_Whitespace
```

## 4. Post-deploy
- Assign `Am_Law_UK_50_Whitespace_Access` to the Rev Ops folder audience (FLS).
- Confirm the report type exposes "Firm: Am Law UK 50 Rank".
- Spot-check the 4 reports + dashboard render (they will be EMPTY until the rank data load in §5).
- Optional: add the Product Family dashboard filter in the UI (deferred; FY filter is N/A under the active-snapshot method).

## 5. Rank data load (50 accounts) — SEPARATE, user-confirmed step
Uses `amlaw_uk50_rank_load_TEMPLATE.csv` (columns: `Id, Account_Name, Am_Law_UK_50_Rank__c`).
1. User provides the 50 firm names + ranks (the source ranking).
2. Resolve names → **firm/ultimate Account Ids** in PROD (read-only) and fill `Id`. Ranks go ONLY on firm/ultimate accounts. Helper:
   `sf data query -o LBR_PROD --query "SELECT Id, Name FROM Account WHERE Name LIKE '%<firm>%'"`
3. Delete the EXAMPLE rows.
4. Validate, then load (on confirmation):
   `sf data update bulk -s Account -f amlaw_uk50_rank_load.csv -o LBR_PROD`  (or Data Loader)
5. Re-render reports/dashboard — they should now populate against real PROD subscription data.

## Rollback
- Field/perm set/report types/reports/dashboard: delete via destructiveChanges or the UI.
- Rank data: clearing `Am_Law_UK_50_Rank__c` to null removes firms from the cohort (filters are `rank != null`).
