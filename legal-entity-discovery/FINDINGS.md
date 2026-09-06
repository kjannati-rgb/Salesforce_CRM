# Legal Entity Overwrite — Production Discovery Findings (READ-ONLY)

**Date:** 2026-07-03 · **Org:** Centellic production (`00D6g0000081IOgEAM`, lawbusinessresearch.my.salesforce.com) · **Author:** CRM discovery (Claude Code session, Kamyar Jannati)
**Jira:** REV-73 · **Evidence trail:** `legal-entity-discovery/` (describes, SOQL results, report describes, CRT metadata — all read-only retrievals)

---

## 1. Scenario verdict: **B** — the entity value was never stored

`Opportunity.LBR_Legal_Entity__c` ("LBR Legal Entity") is a **formula field**:

```
TEXT(Owner.LBR_Legal_Entity__c)
```

It is not writable (`updateable: false`), holds no data of its own, and re-evaluates **at read time** against the owner's *current* `User.LBR_Legal_Entity__c` (a writable picklist with 6 values: ALM Global, LLC / Law Business Research (Asia) Ltd. / Law Business Research (UK) Ltd. / Law Business Research LLC / MBL Seminars Limited / The Business Research Company).

**There is no automation to disable.** No flow, Apex, or integration writes this field — nothing *can* write a formula field. Phase 2 (automation hunt) was skipped per the discovery rules once the formula was proven; there is no recalculation job, no field history, and no "moment of corruption" to find in logs. The corruption is architectural: history was never captured.

Evidence: `describes/describe_opportunity.json`, `describes/describe_user.json`, `evidence/entity_field_candidates.txt`.

### Adjacent fields with the same defect (same fix must cover them)

| Object | Field | Formula |
|---|---|---|
| Opportunity | `Owner_Company_Name__c` | `Owner.CompanyName` |
| SBQQ__Quote__c | `Sales_Rep_Legal_Entity__c` | `TEXT(SBQQ__SalesRep__r.LBR_Legal_Entity__c)` |
| SBQQ__Quote__c | `Quote_Owner_LBR_Legal_Entity__c` | `TEXT(Owner.LBR_Legal_Entity__c)` |
| OpportunityLineItem | `Company2__c`, `Company3__c` | branch on `Opportunity.Owner.LBR_Legal_Entity__c` to derive entity codes (LLC/GHK/LBR) — **labelled "for SUN": these feed the SUN finance extract**, so the finance system inherits the same history-rewriting behaviour |

A writable picklist `Opportunity.Billing_Entity__c` (LBR/GHK/LLC/MBL/ALM) also exists — a separate billing concept, but proof the "stamped picklist on Opportunity" pattern already exists in the org.

## 2. Root cause narrative

**For the CRO (non-technical):** The "Legal Entity" shown on an opportunity is not saved on the opportunity at all. It is a live lookup that says "show me the entity *currently* on this opportunity's owner's user record." So the moment HR/RevOps updates a salesperson's entity, every opportunity they have ever owned — closed years ago or not — instantly displays the new entity. Nothing "ran" and no data was edited on the opportunities; the reports were always displaying a live answer to the wrong question ("who does this person work for *now*?") instead of the right one ("who did they work for *when this deal happened*?").

**Technical detail:** `Opportunity.LBR_Legal_Entity__c` = `TEXT(Owner.LBR_Legal_Entity__c)`, a cross-object formula against the owner's writable picklist. Formula fields store nothing, are recomputed at query/report time, cannot have field history tracking, and leave no audit trail when their displayed value changes. SetupAuditTrail (180-day API window, back to 2026-01-03) contains **zero** changes to any user's `LBR_Legal_Entity__c` value — confirming all four known moves predate January 2026 and that no in-window edit exists to roll back. The same live-traversal pattern is replicated on quotes and — critically — on opportunity line-item formulas feeding the SUN finance extract.

## 3. Damage sizing

User IDs (all active): Rebecca Mogridge `0056g000005rr0QAAQ` (current entity: **Law Business Research LLC**) · Danica Alagon `0056g000005rqzOAAQ` (current: **Law Business Research (UK) Ltd.**) · Joey Kwok `0054L000001164IQAQ` (current: **ALM Global, LLC**; her `CompanyName` still reads "Law Business Research (Asia) Ltd." — the org's own fields disagree with each other).

In every query below, **100% of records** report the owner's current entity — the uniform flip is proven, not sampled. Amounts are summed by `CurrencyIsoCode` (multi-currency org, no conversion applied). `Full_Contract_Value__c` **does not exist** on Opportunity; `Amount` and `Annual_Contract_Value__c` were both summed, but ACV is a conditional formula returning null/negative in aggregates — **use `Amount` for the headline and have Finance confirm the reporting measure.**

### Rebecca Mogridge — should be UK Ltd before 1 Apr 2024; all rows currently show "Law Business Research LLC"

| Cut | Stage | Records | Amount |
|---|---|---|---|
| **CloseDate < 2024-04-01** | Closed Won | 1,026 GBP / 18 EUR / 15 USD | £2,480,360 / €76,859 / $87,508 |
| | Closed Lost | 1,891 GBP / 10 EUR / 49 USD | £11,922,649 / €30,346 / $237,441 |
| | Closed Won – Cancellation | 19 GBP | £0 |
| | **Total** | **3,028** | |
| **CreatedDate < 2024-04-01** | Closed Won | 1,089 GBP / 18 EUR / 22 USD | £2,888,833 / €76,859 / $153,605 |
| | Closed Lost | 1,957 GBP / 10 EUR / 55 USD | £12,386,553 / €30,346 / $274,830 |
| | Open (Identify/Evaluate) + Cancellation | 158 |  |
| | **Total** | **3,289** | |

### Danica Alagon — should be Asia Ltd before 1 Jan 2025; all rows currently show "Law Business Research (UK) Ltd."

| Cut | Stage | Records | Amount |
|---|---|---|---|
| **CloseDate < 2025-01-01** | Closed Won | 581 GBP / 3 USD | £4,355,384 / $19,713 |
| | Closed Lost | 850 GBP / 8 USD | £4,466,425 / $11,465 |
| | Closed Won – Cancellation | 10 GBP | –£18,635 |
| | **Total** | **1,452** | |
| **CreatedDate < 2025-01-01** | Closed Won | 593 GBP / 25 USD | £4,678,199 / $378,544 |
| | Closed Lost | 872 GBP / 34 USD | £4,753,474 / $396,255 |
| | Open + Cancellation | 24 |  |
| | **Total** | **1,548** | |

### Joey Kwok — all years currently show "ALM Global, LLC", including 2021–2024 APAC history

| Close year | Records | Amount |
|---|---|---|
| 2021 | 121 GBP / 6 USD | £395,288 / $19,111 |
| 2022 | 336 GBP / 3 USD | £1,415,676 / $9,588 |
| 2023 | 328 GBP / 8 USD | £1,296,397 / $14,720 |
| 2024 | 391 GBP / 5 USD | £1,574,557 / $11,344 |
| 2025 | 104 GBP / 2 USD | £526,605 / $3,109 |
| 2026 | 129 GBP / 2 USD | £623,315 / $4,934 |
| 2027 / 2030 | 9 GBP | £20,874 |
| **Total** | **1,444** | **~£5.85M / ~$62.8K** |

**Open questions this forces:** (a) ~~by which date field?~~ **ANSWERED 2026-07-03: CloseDate.** The CloseDate cuts above are the authoritative damage/backfill populations (Rebecca 3,028; Danica 1,452). (b) What entity is "correct" per period for each person — the moves themselves (dates + from/to) must come from HR/RevOps, since no system of record captured them. (c) ~~Which measure?~~ **ANSWERED: depends on the product.** `Amount` stands as the common-denominator sizing figure; Finance to supply the product-line → measure map before backfill validation.

### Fourth person — identity TBC (possibly a "Will")

Identity remains **unconfirmed with the business** (2026-07-03). A precautionary candidate scan of users named Will* was run (`soql/will_candidates.json`, `soql/will_users.json`): the only **active** seller with material volume is William Anderson `005Tm000001JILdIAO` — 521 opps, current entity "Law Business Research LLC", book spanning close-years 2025–2029 (~$7.45M USD + ~£0.71M GBP, `soql/will_anderson_by_year.csv`). Other Wills with large books (Will Bull 869 opps, Will Guyatt 500, Will Lovett 203) are deactivated legacy users. No user named "Will Do" exists in PROD. **This is prep work only — the Director of Revenue Operations must supply the fourth person's identity, move date, and from→to entities before anyone is added to the backfill spec.** The damage-sizing queries in this pack are parameterised by User Id and rerun in minutes once confirmed.

CSVs: `soql/rebecca_closedate_cut.csv`, `soql/rebecca_createddate_cut.csv`, `soql/danica_closedate_cut.csv`, `soql/danica_createddate_cut.csv`, `soql/joey_by_year.csv`.

## 4. Blast radius

**Method:** all 6,730 reports inventoried (`reports/report_inventory.csv`); the 4,107 run in the last 12 months were described via the Analytics REST API (4,101 succeeded; 6 returned "report definition is obsolete" — listed in `reports/describe_failures.json`); **2,623 stale reports (no run in 12 months) were not described** and are excluded from the counts below. Raw string matching alone over-counts (3,173 hits) because a describe embeds every column *available* on the report type; classification below counts only reports that **actually use** an entity field.

**Affected reports: 669** (`reports/affected-reports.csv`) — 394 use it as a **filter** (with the filter value captured, e.g. "Law Business Research LLC" ×139, "Law Business Research (Asia) Ltd." ×90), 224 as a column, 129 as a grouping, 21 in bucket fields. Top folders: Public Reports (154), USA – LBR (30), Revenue Operations (28), FY-year folders (2025/FY24/FY25/FY23–FY26 vs Budget ≈ 80 combined), Pipeline Tracker ×2 (44), Events Sales Reports (18), HK (16), **Old Commercial Pack reports (8)** and **Commercial Finance Reports (6)** — the Commercial-Pack lineage is directly implicated. A further 2,504 reports sit on affected CRTs without currently using the field (`reports/reports_on_affected_crts_field_unused.csv`) — no migration needed, but any future edit can pick the poisoned column.

**Affected dashboards: 114 of 371** (`reports/affected-dashboards.csv`), by joining DashboardComponent → affected reports. Includes **! Senior Management Dashboards** ("1.1 Company Performance Dashboard: USA", "MI/Analytics Performance Dashboard"), the Pipeline Dashboards suite, Lexology Index FY25/FY26 HK & USA, and the Events/Webinars FY22–FY26 revenue dashboards. Dashboards inherit from source reports, so migrating the underlying reports fixes them — but entity-filtered dashboards (e.g. every "…US"/"…HK" variant) are exactly where the regional misstatement is visible today.

**Custom Report Types (retrieved all 197 from PROD):** **100 CRTs carry 141 entity-field column references** (`reports/affected-crts.csv`). 72 are Opportunity-based, plus User (10), Lead (7), Order (6), Account (5), SBQQ Quote (4), Campaign (4), Budget, Target, Contract, Customer Journey, eSign Agreement, ForecastingItem. Beyond the Opportunity formula itself, CRTs bake in **direct owner traversals** (`Owner.LBR_Legal_Entity__c`, `Opportunity_Product__c.Opportunity.Owner.LBR_Legal_Entity__c`) and sibling formulas (`LBR_Legal_Entity_for_SUN__c` ×13, `Quote_Owner_LBR_Legal_Entity__c` ×6, Lead `Owner_LBR_Legal_Entity__c`). Any report built on these columns rewrites history the same way regardless of what happens to the Opportunity field — a structural Scenario-B confirmation.

**Out of scope of this analysis (explicit):** Power BI / EBS extracts and any middleware queries sit outside Salesforce metadata — **Anik Bhowmik must audit those queries separately** for `LBR_Legal_Entity__c`, `Owner.LBR_Legal_Entity__c`, `Company2__c/Company3__c`, and `LBR_Legal_Entity_for_SUN__c` references. The SUN extract is *known* to consume the line-item entity formulas (§1).

**Tooling note:** `MetadataComponentDependency` (beta) is not queryable in this org (`RefMetadataComponentName is unknown`); blast radius was therefore established by exhaustive describe + retrieve + grep, per the discovery plan.

## 5. Recommended remediation design (design only — nothing executed)

1. **New stamped field:** `Legal_Entity_Stamped__c` (picklist, same 6 values as `User.LBR_Legal_Entity__c`) on Opportunity, populated by a record-triggered flow (or the existing Apex automation layer) **once at creation** from the owner's then-current entity. Decision point: **re-stamp at Closed Won** (recommended — the entity at the time revenue is booked is what Finance reports) and on **owner change while open** (recommended; a reassigned open deal belongs to the new owner's entity). Never recalculated after close. Enable field history tracking on it.
2. **Backfill (one-time, per person, NOT executed):** for the four movers, set the stamped field on historical records per the HR-confirmed move dates (e.g. Rebecca: records before 1 Apr 2024 → "Law Business Research (UK) Ltd."). Everyone else: backfill = current formula value (owner's current entity), which is correct for non-movers. The per-person correction spec that Anik hand-builds in EBS today becomes the backfill spec, executed once, then retired.
3. **Parallel run:** keep `LBR_Legal_Entity__c` (formula) untouched; both fields coexist. Migrate reports/dashboards folder-by-folder (Commercial Pack folders first), diff the two fields for a full reporting cycle (they should match for non-movers; differ only for the four), then deprecate the formula (rename label to "DO NOT USE — live owner entity", remove from CRT layouts).
4. **Quote/OLI siblings:** apply the same stamp-vs-formula decision to `Sales_Rep_Legal_Entity__c`, `Quote_Owner_LBR_Legal_Entity__c`, and especially the SUN-feeding `Company2__c`/`Company3__c`/`LBR_Legal_Entity_for_SUN__c` — coordinate with Finance before touching the SUN mapping.
5. **"Duplicate user per entity" workaround: REJECT.** It would double licence cost per mover, split pipeline/activity history and targets across two user records, break ownership-based automation (renewals, territory, forecasts, ChurnZero division segmentation via `Opportunity_Owner_Division__c` — another Owner-traversal formula with the same defect), corrupt duplicate-detection and SSO identity, and still not fix the history already rewritten. It treats the user record as a reporting dimension, which is exactly the architectural mistake that caused this.

## 6. Open questions for the business (for REV-73) — with answers received 2026-07-03

1. **(Finance — Anik)** Which measure do Commercial Packs report? → **ANSWERED: depends on the product.** Follow-up owed by Finance: the product-line → measure map, so backfill validation compares the right figure per line. `Amount` remains the sizing common denominator.
2. **(Finance — Anik)** Audit EBS/Power BI/SUN extract queries for the entity fields. → Business asked *what difference it makes*: **it decides whether the fix ends at Salesforce.** If Finance extracts read the formula field (or join to the user's current entity), their history rewrites on every refresh — Anik's hand-built corrections sit on data that shifts underneath them, and they change again on the next mover. If the extracts read something stored, Finance is unaffected. It also gates cutover: after the stamped field + backfill ships, any extract still pointed at the formula keeps consuming poisoned values, and the incident can't be declared closed. At least one feed is already proven exposed — the SUN line-item formulas (§1). Deliverable stands: list which extract queries reference `LBR_Legal_Entity__c` / `Owner.LBR_Legal_Entity__c` / `Company2__c` / `Company3__c` / `LBR_Legal_Entity_for_SUN__c`.
3. **(RevOps — Director)** Fourth person identity → **STILL TBC** (business does not know yet). Candidate scan done as prep (§3); move dates + from→to entities also still needed for all four movers.
4. **(RevOps)** Cut date field → **ANSWERED: CloseDate.** §3 CloseDate tables are authoritative.
5. **(RevOps + Finance)** Stamping policy (creation-only vs re-stamp at Closed Won / owner change) → **TBC.** Design proceeds with the §5 recommendation (stamp at creation, re-stamp at Closed Won and on owner change while open) until overruled.
6. **(CRM — Kamyar)** Sibling-field remediation sequencing → Business asked *what difference it makes*: **if only the Opportunity field is fixed, the problem recurs in Finance.** The quote and line-item entity formulas flip exactly the same way, and the line-item ones (`Company2__c`/`Company3__c`/`LBR_Legal_Entity_for_SUN__c`) code revenue for the SUN extract. Fix only the Opportunity field and Commercial Packs are cured, but the next entity move silently re-corrupts the finance feed — same incident, new venue, discovered by Anik again. The question was only about sequencing and who signs off the SUN mapping change, not whether to do it.
7. **(RevOps)** Other historical movers beyond the four? → **ANSWERED: NO.** Backfill scope is fixed at four people.
