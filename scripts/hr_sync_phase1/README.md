# HR to Salesforce employee sync, Phase 1

Writes HR-sourced values onto User and Contact records for current employees, using the Id mapping workbook as given.
Brief: `Claude_Code_Brief_HR_to_Salesforce_Phase1.md` (Kam's Downloads; v3 after preflight). Read it first; the gates in it are real stops.

## Files

| File | Purpose |
|---|---|
| `build_changes.py` | Step 1 / Step 3.3. Reads HR extract + mapping, queries the target org, writes the change set, update parts, backups, rollbacks and `dry_run_report.md`. No DML. |
| `apply.py` | Step 2.2 / 3.4. Loads `parts/update_*.csv` with `sf data update bulk`, one file at a time. Stops on validation/flow errors or more than 1 percent failures. Records job Ids and result files. |
| `verify.py` | Step 2.4 / 3.4. Re-queries every record, diffs against the intended values with the shared comparison rules, checks baseline fields for side effects, counts `Flow_Log__c` since run start, re-runs the build for the idempotency count. `--second-read` re-checks the three flags later. |
| `name_check_exceptions.csv` | Kam-approved Ids whose org name does not carry the HR surname but are the same person (matched on email). Written, not skipped. |
| `exclusions.csv` | Kam-approved Ids never written in any org (e.g. a system user the mapping matched on email). |
| `preflight/` | Step 0 evidence for Full UAT: describes, retrieved flows, sbaa dumps, report grep. Large dumps are gitignored. |
| `preflight_FULLUAT.md` | Step 0 report. |
| `out_<org>/` | Everything a run produces. `out_FULLUAT/` is the sandbox rehearsal of 8 Sep 2026. |

## Running against a new HR extract and mapping

1. Copy the HR workbook out of OneDrive (the sandboxed interpreter cannot open the OneDrive path) and point `DEFAULT_HR` / `DEFAULT_MAP` at the new files, or pass `--hr` and `--mapping`.
   The HR sheet must keep headers on row 2 (Employee ID, Worker, Preferred Name, Business Title, Worker's Manager, Email - Work). The mapping must keep Employees columns A/C/AD/AE/AF and Users columns K/N; the loader asserts them.
2. Step 0: repeat the preflight items against the target org (see the brief). `preflight/` scripts are reusable: `quantify_missing.py <org>` for Id resolution, `item7_contacts_and_lengths.py <org>` for flags and lengths.
3. Step 1: `python build_changes.py --org <alias>`. Read `out_<alias>/dry_run_report.md`. Sandboxes (`FULLUAT`, `KJDEV`) log and skip missing, inactive and name-check-failed Ids; `PROD` aborts on any of them unless the Id is in `name_check_exceptions.csv`. Gate 1.
4. Step 2: `python apply.py --org <alias>` (default batches `user,contact,manager`; `--batches` to restrict; `--dry` to print the commands). Then `python verify.py --org <alias> --label sandbox`, wait a few minutes, `python verify.py --org <alias> --label sandbox --second-read`. Gate 2.
5. Step 3 (production): only on Kam's literal reply GO PROD. `apply.py` refuses production unless the environment variable `GO_PROD` is set to `GO PROD`. Rebuild against production first; the sandbox change set is never reused.

### Workday extension (8 Sep 2026)

`build_changes.py` also writes the Workday block from the team brief: standard `Department`, `Division` (nine allowed values, others skipped and logged) and `CompanyName`, plus the custom fields `Workday_Employee_ID__c`, `Hire_Date__c`, `Sub_Division__c`, `Location__c`, `Employee_Type__c`, `ELT_Lead__c` and `Workday_Last_Sync__c`. Rules:

- A custom field is written only if the target org has it (the build describes User first and reports which are missing). Full UAT and production get them after `workday_fields/generate_metadata.py --org <alias>` is deployed there.
- A restricted-picklist value the org does not have is skipped and logged ("add the value first"), never forced.
- ELT Lead resolves like Manager: Workday name to HR Preferred Name to the mapping's primary user, active only. Inactive leads are skipped and listed.
- `Workday_Last_Sync__c` is stamped only on rows that carry another change, so a second build still produces zero rows.
- `--hold-fields` (default `EmployeeNumber,Employee_Code__c`) holds the D6 fields; `--users-only` skips Contact for KJDEV smoke tests.

Comparison rules (build and verify share them): Title trimmed and case-insensitive; EmployeeNumber, Employee_Code__c, Employee_Number__c exact string; Ids 18-character; blank in HR means skip, never clear; the only deliberate clears are the three not-at-company flags.

## If a load stops part-way

`apply.py` loads parts in order and stops on the first part that breaks a rule. Records already loaded stay loaded; the build is idempotent, so re-running `build_changes.py` produces only what is still missing. To keep the original backups and rollbacks as the run of record, rebuild into a sub-folder and load from it:

```
python build_changes.py --org FULLUAT --out out_FULLUAT/continue1
python apply.py --org FULLUAT --parts-dir out_FULLUAT/continue1 --batches contact,manager
```

`verify.py` reads skip lists from `out_<org>/skipped_ids.json` and every `continue*/skipped_ids.json`, so rows skipped in a continuation count as logged skips, not mismatches.

## Rollback

```
sf data update bulk --sobject User --file out_<org>/parts/rollback_user_001.csv --line-ending CRLF --target-org <alias>
```

One file per part, same order as the load (`rollback_user_*`, `rollback_contact_*`, `rollback_user_manager_*`). The full pre-run values of every in-scope and baseline field are in `backup_<orgId>_<ts>_<object>.csv`. Re-run `verify.py` afterwards; the intended-values section will show mismatches equal to the number of rolled-back rows, and the side-effect section must stay empty.

## Gotchas learned on the Full UAT rehearsal (8 Sep 2026)

- `sf data update bulk` is Bulk API 2.0: no batch size, no serial mode. Sequential 200-row files are the substitute. `--line-ending CRLF` matches the files this script writes.
- When a job completes with some failed rows, the CLI exits 1 with `FailedRecordDetailsError` and the job Id sits in `data.jobId`, not `result`. `apply.py` handles that; `sf data bulk results --job-id` writes the success/failed CSVs.
- `Contact.Employee_Number__c` is a unique external Id. Where a surplus duplicate contact already holds the HR number, the write fails with `DUPLICATE_VALUE`; the build now pre-checks holders and skips those rows with the holder Id logged. Phase 2 merge item.
- `User.Manager_Email__c` is a formula; it is verified, never written.
- The change CSVs union columns across rows, so an empty cell means "not changed on this row". The Bulk API parts are split by column set so an empty cell is never sent (it would clear the field).
- HR "Worker" names can carry an "(On Leave)" suffix; two-letter surnames (So, Yu, Ng, Lo) need the whole-name equality path in the name check.
- Validation rule `Not_at_Company_Flag` blocks edits to flagged contacts for most profiles. Run as a System Administrator.
