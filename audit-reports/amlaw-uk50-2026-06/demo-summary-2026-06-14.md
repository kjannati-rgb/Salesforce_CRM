# Am Law UK 50 Whitespace — KJDEV Demo Output (2026-06-14)

**Org:** KJDEV (sandbox). **Purpose:** structure validation — KJDEV opp data is stale, so numbers are not real.

## Dummy ranks loaded (5 firm/ultimate accounts)
| Rank | Firm (Ultimate Account) | Real Am Law UK 50 name? |
|---|---|---|
| 1 | Clifford Chance (SCDEMO) | yes |
| 5 | Dentons (SCDEMO) | yes |
| 9 | Baker (SCDEMO) | yes (Baker McKenzie) |
| 18 | Helios Legal (SCDEMO) | no (demo firm) |
| 27 | Reyes IP (SCDEMO) | no (demo firm) |

Ranks written to `Account.Am_Law_UK_50_Rank__c` on the firm-level (ultimate) accounts only.

## What rendered (all reports executed via Analytics API, no errors)
| Report | Format | Result | Why |
|---|---|---|---|
| Whitespace (Current) | Matrix | runs OK, **empty** (grand total 0) | KJDEV has **0 Closed Won** opps, so the active-snapshot filter matches nothing |
| Whitespace (Last Yr) | Matrix | runs OK, **empty** | same |
| Whitespace YoY | Joined (multi-block) | runs OK, cross-block YoY = GBP 0.00 | same; the **YoY £/% cross-block formulas execute** |
| Never-Served (live, A) | Tabular + cross-filter | **5 rows** (all cohort firms) | every ranked firm has no Closed Won opp → all are "never served" |

**Structural validation confirmed:** rank field, firm-grain grouping/sort, corrected 11-family filter, cross-block YoY formulas, and the Account→Opportunity(Ultimate) cross-filter all execute against live KJDEV data without error.

## Never-Served list — A (live) and C (precise) coincide here
With zero coverage data, the live cross-filter report (A) and the precise "cohort firms absent from the Current matrix" (C) return the **same 5 firms**. See `demo-output-2026-06-14.csv`. In production (real subscription data) they will differ: A counts a firm "served" if it has any won opp in any family; C counts only firms with an active subscription in the 11 target families.

## Caveat
Because KJDEV has no Closed Won / active-subscription data, the matrices and YoY show no cells. This is expected sandbox behaviour, not a build defect — the same metadata against production data will populate. To preview populated matrices in the sandbox would require fabricating Closed Won opportunities + active line items (not done; only ranks were loaded, as authorised).
