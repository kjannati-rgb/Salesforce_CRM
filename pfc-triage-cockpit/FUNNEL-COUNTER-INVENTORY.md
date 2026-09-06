# Funnel Counter Fields — Consumer Inventory (E2)

**Fields:** `Identify__c`, `Qualify__c`, `Evaluate__c`, `Close__c`, `Closed_Won__c`, `Closed_Lost__c` on `Pardot_Form_Completion__c`.
**Scope:** documentation only — retirement goes through the field-retirement taxonomy process, not this project. The fields are already removed from the new cockpit page (they never were "layout" data; they're 0/1 numeric counters for report math).

## Method
1. **Dependency API** (Tooling `MetadataComponentDependency`, prod, 2026-07-15): 0 consumers for all six fields. Method validated by control query on `Sales_Stage__c` (92 consumers: 84 Flow, 4 VR, 2 Layout, 2 FlexiPage). Note: this API does **not** index Reports in this org — hence step 2.
2. **Report scan:** grepped the REV-73 cached Analytics describes — all 4,101 prod reports **run in the 12 months to 2026-07-03** — for qualified column tokens, restricted to `reportMetadata` (columns/groupings/filters actually on the report, not the report type's field catalogue — matching the raw JSON over-counts 131→99, and matching bare field names over-counts to 2,596 because `Close__c`/`Closed_Won__c` also exist on Opportunity).

## Findings

| Field | Metadata consumers | Reports using it (12-mo run window) | Verdict |
|---|---|---|---|
| `Identify__c` | 0 | **0** | retire candidate — nothing references it |
| `Qualify__c` | 0 | **0** | retire candidate |
| `Evaluate__c` | 0 | **0** | retire candidate |
| `Close__c` | 0 | **0** | retire candidate |
| `Closed_Lost__c` | 0 | **0** | retire candidate |
| `Closed_Won__c` | 0 | **99 reports** | KEEP until report migration |

Full report list: `funnel-counter-report-hits.csv` (Id, name, folder, fields). The 99 are the "% won / conversion" report family — all built on CRT `Custom_Pardot_Form_Completions_with_Opps__c`, concentrated in ~6 folders (marketing analytics, ALM EVT copies, Scored Leads copies, "MA Copy" folder, personal folders). They SUM `Closed_Won__c` as the numerator for form→sale conversion rates.

## Recommendation (for the retirement ticket, not this project)
- Five of six fields can enter the retirement taxonomy immediately (describe-window caveat below).
- `Closed_Won__c` needs a replacement metric first. `Converted_to_Sale__c` (existing checkbox) likely carries the same semantics — verify parity on a sample, then repoint the 99 reports (bulk describe/patch via Analytics REST is scriptable) before retiring.
- Quick win regardless: much of the 99 is copy sprawl (at least 4 near-identical folder clones of the same 12-report set) — a report-folder cull shrinks the migration to ~25 unique reports.

## Caveats
- Coverage = reports **run** in the 12 months to 2026-07-03. Stale/unrun reports aren't described; dashboards inherit from source reports (a dashboard on an unrun report wouldn't appear — rare, since dashboard refreshes run the reports).
- Cache is 12 days old; reports built after 2026-07-03 aren't in it. Re-run `legal-entity-discovery/describe_reports.py` style collection before executing any retirement.
