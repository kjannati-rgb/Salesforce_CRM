# Kickoff — Law.com Tech Touch CSM bulk load (REV/CRM Support request, Chris Riley, 3 Jul 2026)

## Objective
For 2,523 production Firm Accounts (per Chris Riley's spreadsheet):
1. Insert an **AccountTeamMember** record: user `005Px00000Bnj46IAB` ("Tech Touch CS Law.com"), role **Law.com CSM**.
2. Update Account field **`ALM_Service_Level__c`** (label: "Law.com Service Level") to **`Tech Touch`**.

Target org: **production** (org ID 00D6g0000081IOg). This is a data-only load — no metadata changes. Do not deploy anything.

## Inputs (already prepared and validated)
- `AccountTeamMember_insert.csv` — 2,522 rows. Columns: AccountId, UserId, TeamMemberRole, AccountAccessLevel (Edit), OpportunityAccessLevel (Read), CaseAccessLevel (None), ContactAccessLevel (Edit). Access levels mirror the user's 1,093 existing team memberships exactly.
- `Account_service_level_update.csv` — 2,523 rows. Columns: Id, ALM_Service_Level__c.

## Pre-verified facts (3 Jul 2026, read-only via MCP)
- User `005Px00000Bnj46IAB` is active (Profile: Read Only, Standard user type).
- User already holds 1,093 AccountTeamMember records, all role "Law.com CSM", all with the access-level combo above.
- Exactly **1 account** in the sheet already has this user on its team — `001Px00000VvipqIAB` (Hofstra University OGC) — excluded from the insert CSV, but still included in the service-level update.
- `ALM_Service_Level__c` is an active picklist on Account; `Tech Touch` is a valid value.
- Sheet validation: 0 duplicate IDs, 0 blanks, all IDs valid 001-prefixed.

## Phase 0 — Pre-flight (read-only, required before any write)
1. Confirm target org alias resolves to production 00D6g0000081IOg (`sf org display`).
2. Verify all 2,523 Account IDs exist and are not deleted/merged: chunked queries (e.g. 500 IDs per `WHERE Id IN (...)`), `SELECT Id, IsDeleted, RecordType.Name, ALM_Service_Level__c`. Report:
   - any missing/deleted IDs (remove from both CSVs, log them),
   - RecordType distribution (expectation: Firm accounts — flag anything that isn't),
   - current `ALM_Service_Level__c` distribution (how many are already 'Tech Touch', how many hold a different value that we're about to overwrite — **pause and report if any are High/Mid/Low Touch**, since overwriting a higher-touch tier may need Chris's confirmation).
3. Capture rollback snapshot: export current `Id, ALM_Service_Level__c` for all 2,523 accounts to `rollback_account_snapshot.csv`.

## Phase 1 — Load (Bulk API 2.0, only after Phase 0 report is confirmed by Kam)
```bash
# Team member inserts
sf data import bulk --sobject AccountTeamMember --file AccountTeamMember_insert.csv --target-org <PROD_ALIAS> --wait 15

# Account field update
sf data update bulk --sobject Account --file Account_service_level_update.csv --target-org <PROD_ALIAS> --wait 15
```
Run the team-member insert first (independent of the field update). Capture job IDs; retrieve failed-record CSVs for any failures.

## Phase 2 — Post-verification
1. `SELECT COUNT(Id) FROM AccountTeamMember WHERE UserId = '005Px00000Bnj46IAB'` — expect 1,093 + 2,522 = **3,615** (minus any Phase 0 exclusions).
2. Chunked re-query of the 2,523 accounts — confirm all show `ALM_Service_Level__c = 'Tech Touch'`.
3. Produce a summary for reply to Chris Riley (cc Laura Murr): counts loaded, exclusions, failures with reasons.

## Guardrails
- No writes before Kam confirms the Phase 0 report.
- Bulk API only; no anonymous Apex DML.
- Any partial-failure batch: stop, report failed rows, do not retry blindly (AccountTeamMember inserts can fail on inactive owner, private accounts owned by inactive users, etc.).
- Keep rollback snapshot and job IDs in the working folder.
