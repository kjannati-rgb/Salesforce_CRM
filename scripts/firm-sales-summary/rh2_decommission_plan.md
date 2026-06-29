# rh2 Decommission & Consumer-Migration Plan

**Goal:** retire the legacy Rollup Helper (`rh2`) fields once the Firm Sales Summary feature fully
covers their consumers. **Status: BLOCKED** — Q9 ("nothing reads the rh2 fields") is false, and a
**grain mismatch** means a like-for-like swap isn't yet possible.

## The four rh2 fields
`Val_of_Won_Office_Opportunities__c`, `No_of_Won_Office_Opportunities__c`,
`CFY_Val_of_Won_Office_Opportunities__c`, `CFY_No_of_Won_Office_Opportunities__c`.

## ⚠️ Critical: grain mismatch
| | rh2 | Firm Sales Summary (new) |
|---|---|---|
| **Firm accounts populated** | 209,617 | ✅ all firms-with-won-opps |
| **Office accounts populated** | **255,573** | ❌ **none** (office breakdown is live-in-LWC only) |

rh2 maintains the rollup on **both** the Firm (firm-total) *and* each Office (per-office). The new
engine persists **firm-grain only** (brief §4: "Office breakdown stays live in the LWC … promote it
the same way later if office-level reporting is ever needed"). The firm-grain numbers are verified
equivalent (reconciliation: Baker McKenzie rh2 1042 = new 1042). **Any consumer that reads the rh2
field on an *Office* account cannot be repointed to the firm fields** until office-level rollups are
persisted.

## Field mapping (firm-grain, on the Firm account)
| rh2 | → new | Caveat |
|---|---|---|
| `No_of_Won_Office_Opportunities__c` | `Firm_Won_Count_AllTime__c` | direct equivalent (count) |
| `CFY_No_of_Won_Office_Opportunities__c` | `Firm_Won_Count_CFY__c` | direct equivalent (count) |
| `Val_of_Won_Office_Opportunities__c` | `Firm_Won_Value_AllTime_USD__c` | **basis change: legacy GBP → USD, and net-of-cancellation** |
| `CFY_Val_of_Won_Office_Opportunities__c` | `Firm_Won_Value_CFY_USD__c` | **GBP → USD** |

## Consumers & migration disposition
| Consumer | Reads | Grain | Disposition |
|---|---|---|---|
| **SalesMotionService** `firmHasWonBusiness()` | `SUM(No_of_Won…)` over firm+offices, only needs `> 0` | firm | ✅ **Migrate now** → `[SELECT Firm_Won_Count_AllTime__c FROM Account WHERE Id=:firmId] > 0` |
| **LeadMatchSelectService** | `No_`, `Val_`, `CFY_No_` → `wonOppCount`/`wonOppValue` (primary sort + display + compare) | **office** (match candidates) | ⛔ **Blocked on office-grain.** Also `wonOppValue` display/label changes GBP→USD |
| **SmartConvertController** | `No_of_Won…` → "N won opps" in match results | **office** | ⛔ **Blocked on office-grain** |
| **FlexiPage `Account_Record_Page4`** | displays all 4 (Firm page) | firm | ✅ Swap to the new USD fields (relabel "(USD)"); the `firmSalesSummary` LWC already supersedes them |
| **Layout `Account-Firm Layout`** | "LBR Firm Spend" sections | firm | ✅ Swap to the new fields (the `Firm Sales Summary (USD)` section is already added) |
| **Permset `ALM_fields_data_team`** | FLS | n/a | Grant FLS on the new fields, then drop rh2 from the set |

> **Verify** (one query) that LeadMatchSelectService / SmartConvertController candidates are Office
> records, confirming office-grain is required: inspect their match WHERE clauses + sample inputs.

## Phased plan
**Phase 0 — close the grain gap (prerequisite for the office-grain consumers).**
Promote the office breakdown to persisted, exactly as the firm rollups: add the same value/count
fields to the **Office** account (or a `Firm_Office_Rollup__c` child), maintained by the *same*
`FirmRollupService` (it already aggregates per office for the live LWC). Backfill + add to the
nightly batch. ~1–2 days of work, no new architecture.

**Phase 1 — migrate firm-grain + UI consumers (do now, low risk).**
1. `SalesMotionService.firmHasWonBusiness` → read `Firm_Won_Count_AllTime__c` on the firm.
2. FlexiPage `Account_Record_Page4` + `Account-Firm Layout` → swap rh2 fields for the new USD fields (relabel value as USD). The LWC already covers this surface.
3. `ALM_fields_data_team` → add new-field FLS.
4. Deploy + regression-test the two services.

**Phase 2 — migrate office-grain consumers (after Phase 0).**
Repoint `LeadMatchSelectService` + `SmartConvertController` to the new **office** rollups. Note the
**value display flips GBP→USD** — confirm with the lead-gen owners that USD is acceptable in those
screens (ranking is unaffected; only the printed figure + label change).

**Phase 3 — prove zero consumers.**
Re-run `./scripts/firm-sales-summary/reference_scan.sh FULLUAT` (and PROD). Gate: **0 CONSUMERS**
(layout/permset references that merely *display* are fine to retire alongside).

**Phase 4 — deactivate rh2, soak.**
Deactivate the rh2 rollup definitions (stop the jobs). Monitor `Firm_Rollup_Last_Refreshed__c` +
nightly batch for ~1–2 weeks. The new fields are now the system of record.

**Phase 5 — delete.**
Delete the 4 rh2 fields + leftover `rh2__*` test fields; uninstall the rh2 package if otherwise
unreferenced.

## Rollback
The new fields are additive and independent of rh2. At any phase before Phase 5, reverting a
consumer to the rh2 field is a one-line change; rh2 keeps running until Phase 4.
