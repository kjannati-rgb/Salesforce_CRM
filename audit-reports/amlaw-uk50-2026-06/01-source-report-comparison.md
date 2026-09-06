# Am Law UK 50 Whitespace — Task 1: Source Report Comparison (PROD, read-only)

**Date:** 2026-06-13
**Org:** LBR_PROD (production), retrieved read-only via Metadata API
**Author:** kjannati
**Source folder:** Revenue Operations (`Revenue_Operations`, Report folder, AccessType = Hidden)

Two reports retrieved and decoded below. Raw metadata saved under
`audit-reports/amlaw-uk50-2026-06/retrieved/`.

| | CY report | LY report |
|---|---|---|
| Name | Active E&I + Pro + SPG + Docket | LY Active E&I + Pro + SPG + Docket |
| Id | 00OPx000004MgW9MAK | 00OPx000004MrxpMAC |
| Developer name | `Active_E_I_Pro_SPG_Docket` | `LY_Active_E_I_Pro_SPG_Docket` |
| Format | Matrix | Matrix |
| Report type | `Custom_Opportunities_with_Products__c` | `Custom_Opportunities_with_Products__c` |
| Currency | GBP | GBP |
| Scope / role filter | organization / Chief_Executive_Officer | organization / Chief_Executive_Officer |

The two reports are **byte-for-byte identical except for two things**: the date
anchor (TODAY vs 365 days ago) and the Product Family token list. Everything
else — report type, groupings, summarized fields, won/active logic — matches.

---

## 1. Report type
`Custom_Opportunities_with_Products__c` — a custom report type ("Custom
Opportunities with Products"). Confirmed identical on both. This is the type the
new matrix should reuse.

## 2. Groupings (the matrix shape)
| Axis | Field | Notes |
|---|---|---|
| Rows (groupingsDown) | `Opportunity.Ultimate_Account__c` (**Ultimate Account = the firm**) | sorted **Asc by firm name**, NOT by a rank |
| Columns (groupingsAcross) | `OpportunityLineItem.Product_Family__c` | single column grouping |

**There is NO Close Date / Fiscal Year grouping anywhere.** CY vs LY is achieved
by running **two separate reports** with different date anchors — not by a FY
column grouping inside one matrix.

`Ultimate_Account__c` is a **lookup to Account** (relationship `Ultimate_Account__r`).
So the firm-level row is itself an Account record — a rank field on Account can
live on the ultimate (firm) account.

## 3. Summarized fields (revenue)
Three measures are summed, **all `.CONVERT`** (converted to the report currency, GBP):
1. `Opportunity.Annual_Contract_Value__c` — **opp-level ACV**
2. `OpportunityLineItem.TotalPrice` — line item contract total
3. `OpportunityLineItem.Annual_Contract_Value__c` — **line-item ACV**

There is no single "the" revenue column flagged — all three render at each cell.
For a **product-family matrix**, only a **line-item** measure is correct: the
opp-level ACV (#1) would post the whole opportunity's value into *every* product
family column the opp touches (double-counting). #2 (Total Price) is contract
total, not annualized. **#3 (line-item ACV, converted) is the right "spend"
measure for this matrix.** → decision needed (see below).

There is also one inactive custom summary formula, `FORMULA1` "Unique Accounts" =
`Opportunity.Account.Name:UNIQUE` (defined, `isActive=false`, not displayed).

## 4. Filters — "won / active" logic
Boolean filter (identical on both): `1 AND 2 AND (3 OR 4) AND (5 OR 6) AND 7 AND 8 AND 9`

| # | Column | Operator | Value (CY) | Value (LY) |
|---|---|---|---|---|
| 1 | Opportunity.StageName | equals | Closed Won | Closed Won |
| 2 | Opportunity.Name | notContain | cancel,delete,test,duplicate | (same) |
| 3 | OLI.Start_Date__c | ≤ | **TODAY** | **N_DAYS_AGO:365** |
| 4 | OLI.Start_Date_SUN_Report__c | ≤ | **TODAY** | **N_DAYS_AGO:365** |
| 5 | OLI.End_Date__c | ≥ | **TODAY** | **N_DAYS_AGO:365** |
| 6 | OLI.End_Date_SUN_Report__c | ≥ | **TODAY** | **N_DAYS_AGO:365** |
| 7 | Opportunity.Cancelled__c | equals | 0 | 0 |
| 8 | Opportunity.Amount | ≥ | GBP 0 | GBP 0 |
| 9 | OLI.Product_Family__c | contains | *(see §5)* | *(see §5)* |

**What this logic actually measures:** an *active-subscription snapshot*. A line
item counts if its contract window straddles the anchor date — Start ≤ anchor ≤ End.
- CY = "active **today**."
- LY = "active **exactly 365 days ago**."

This is **point-in-time live coverage**, *not* bookings/spend closed within a
fiscal year. The deck's "Current FY vs Last FY spend" is, in the data, "summed ACV
of subscriptions active now vs a year ago."

`timeFrameFilter` exists but is inert: dateColumn `Budget_Renewal_Date__c`,
`INTERVAL_CUSTOM` with **no start/end dates** → no standard date restriction applied.

No `roleHierarchyFilter` cohort beyond CEO/organization scope.

## 5. Cohort identification — **no hardcoded account list exists**
> The brief expected "likely a hardcoded account name list" to identify the
> Am Law UK 50 cohort. **There is none.** Neither report filters by Account at all.
> Both return *every* firm with active subscriptions in the chosen families.

The Am Law UK 50 cohort is therefore selected **manually downstream** (the manual
deck step we're replacing). This directly validates the project: `Am_Law_UK_50_Rank__c`
on Account becomes the in-report cohort filter that removes the manual step.

## 6. Product Family filter — token mismatch between CY and LY
`Product_Family__c` is a **formula** field: `Text(PricebookEntry.Product2.Family)` —
it mirrors the `Product2.Family` picklist as text, so the filter `contains` tokens
are substring matches against the real family names (35 active values in prod).

**The two reports use DIFFERENT token lists** (verbatim):
- **CY:** `Expert Insight -Performance, Specialist, Panoramic, In-Depth, Index, Lexology Pro, Specialist Platforms, Docket, Lexology Intelligence, Compete`
- **LY:** `Expert Insight -, Performance, Specialist, Panoramic, In-Depth, Index, Lexology Pro, Specialist Platforms, Docket, Intelligence, Compete`

Resolving substrings against the real `Product2.Family` values:

| Real family | Matched in CY? | Matched in LY? |
|---|:--:|:--:|
| Expert Insight - GXRs | ❌ | ✅ (`Expert Insight -`) |
| Expert Insight - IP | ❌ | ✅ (`Expert Insight -`) |
| Expert Insight - Lexology In-Depth | ✅ (`In-Depth`) | ✅ |
| Expert Insight - Lexology Panoramic | ✅ (`Panoramic`) | ✅ |
| Performance Data - GxR/IP | ❌ | ✅ (`Performance`) |
| Performance Data - Lexology Index | ✅ (`Index`) | ✅ |
| Subs - Specialist Platforms | ✅ | ✅ |
| Subs - Lexology Pro | ✅ | ✅ |
| Subs - Docket Navigator | ✅ (`Docket`) | ✅ |
| Subs - Lexology Intelligence | ✅ | ✅ |
| Subs - Lexology Compete | ✅ (`Compete`) | ✅ |
| **Family count** | **8** | **11** |

**Root cause:** CY's `Expert Insight -Performance` is a broken token — a lost comma
fused `Expert Insight -` and `Performance` into one substring that matches **no**
family. As a result **CY silently omits 3 families that LY includes**
(Expert Insight - GXRs, Expert Insight - IP, Performance Data - GxR/IP). The
existing deck's CY-vs-LY comparison is therefore **not apples-to-apples** on the
product dimension.

---

## 7. Discrepancies vs the build brief (Tasks 2–4) — decisions needed

| # | Brief says | Source actually does | Impact |
|---|---|---|---|
| D1 | Columns: Product Family **then Close Date by Fiscal Year**; YoY via `PREVGROUPVAL` across the FY grouping | **No FY grouping.** CY vs LY = two date-anchored snapshots (active today vs 365d ago). "Spend" = ACV of *active* subs. | **Keystone.** A single matrix with a FY column + `PREVGROUPVAL` measures *bookings closed per FY* — a different number and meaning than the deck. To reproduce the deck you keep the active-snapshot method, and YoY is two snapshot columns, not `PREVGROUPVAL`. |
| D2 | Rank on **Account**; rows by **Account Name** | Rows by **Ultimate Account** (firm). `Ultimate_Account__c` → Account. | Am Law UK 50 is a *firm* ranking. Grouping by Account Name can split one firm across office rows. Cleanest: rank on the firm/ultimate Account, rows by Ultimate Account. |
| D3 | "five E&I families + Subs - Lexology Pro" (6) | 8 (CY) / 11 (LY) families, inconsistent between the two | Need an agreed, single family set used for *both* CY and LY (fix the broken token). |
| D4 | "same revenue field Daniel used" (singular) | 3 summed measures | Pick one. Recommend line-item ACV (converted) for a per-family matrix. |

These are put to the user before any build proceeds.
