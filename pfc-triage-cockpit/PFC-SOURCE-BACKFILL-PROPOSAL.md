# PFC_Source__c Backfill — Proposal (E3, NOT executed)

**Status: PROPOSAL ONLY.** Prod data change — requires its own approval + change record per the project protocol. Suggested Jira: REV ticket referencing REV-76 (the null-RecordType backfill this pairs with).

## Population (prod, measured 2026-07-15)

61,165 records have `PFC_Source__c = null` (the orchestrator has stamped it on new records since the June 2026 REV-57 cutover; everything older is null). Only 13 of them lack a `Form_Name__c`, so derivation coverage is 99.98%.

| Bucket | Count | Proposed value | Rule |
|---|---|---|---|
| RT `Form_Completion` | 13,465 | `Inbound Form` | record type is authoritative |
| RT `Scored_Leads` | 444 | `Scored Lead` | record type is authoritative |
| RT `Events_Sponsorship` | 99 | `Event` | record type is authoritative |
| RT null, Form_Name matches `%Lead scoring%` / `%MQL%` | 49 | `Scored Lead` | form-name pattern |
| RT null, everything else with a Form_Name | ~47,095 | `Inbound Form` | pre-REV-57 creator flow only handled inbound `PFC:` tasks at scale; EVT/newsfeed patterns measured at 0 in this bucket |
| No Form_Name at all | 13 | leave null | not classifiable; ignore |

Cross-checks run: null-RT bucket contains 0 `EVT%`/`%Sponsor%` and 0 `%Newsfeed%` form names.

## Execution plan (when approved)

1. Re-run the counts above same-day (they drift as reps work records).
2. Anonymous-Apex batched updates (Database.update, allOrNone=false, 2k batches) **as a user with the Application_Settings__c automation bypass enabled** — otherwise PFC_On_Save re-stamps names and the task-reminder flow logs 61k Flow_Log rows. The lock VR (`Coverted_Form_Cant_Be_Edited`) blocks non-exempt edits of closed records — run as System Administrator (exempt).
3. Field history is NOT tracked on PFC_Source__c — record before/after counts in the change record for auditability.
4. Verify: `PFC_Source__c = null` count drops to ≤13; spot-check 20 records per bucket.
5. Rollback: values were all null before — a stored CSV of updated Ids (export before update) allows a null-reset if needed.

## Coordination notes

- **Do this together with REV-76** (null-RecordType backfill, 47,157 records — same population, same batching, same bypass requirements). One pass can stamp both fields.
- After backfill, PFC_Source becomes reliable for the cockpit's Attribution tab and E1 list views on historical data.
