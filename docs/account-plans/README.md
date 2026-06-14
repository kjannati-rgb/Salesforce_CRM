# Account Plans — White-Space module (deployable slice)

A native, object-backed slice of the Centellic Account Plans architecture: the plan node,
the white-space matrix, the column config, and the `whitespaceMatrix` LWC that renders the grid.
Segment-aware for **Law Firm** and **Corporate / in-house**.

## What's in this package

| Metadata | API name | Purpose |
|---|---|---|
| Custom object | `Account_Plan__c` | Plan node. Record types `Law_Firm` / `Corporate`. SWOT, tier, deal model, roll-ups (`Total_ARR__c`, `Headroom__c`). |
| Custom object | `Whitespace_Cell__c` | Keystone. One row per product family × node. Master-detail to the plan; `State__c` history enabled. |
| Custom object | `Plan_Product_Family__c` | Config-driven matrix columns + segment relevance (`Relevant_Law_Firm__c` / `Relevant_Corporate__c`). |
| Custom object | `Plan_Stakeholder__c` | Relationship map: contact role, `Influence__c`, `Sentiment__c` (history on), `Reports_To__c` self-lookup. |
| Custom object | `Plan_Objective__c` | Strategic objectives with `Progress_Pct__c`, `Status__c`, `Linked_Family__c`. |
| Apex | `AccountPlanController` | `getMatrix` / `getStakeholders` / `getObjectives` (cacheable). |
| LWC | `whitespaceMatrix` | Colour-coded white-space grid on the plan record page. |
| LWC | `stakeholderMap` | Influence × sentiment relationship heat-map. |
| LWC | `objectivesPanel` | Objectives with progress bars. |
| App / tabs | `Account_Planning` + 5 tabs | Navigation. |
| Permission set | `Account_Plan_Admin` | Object + field + tab + record-type + Apex access. |

### Why a custom `Account_Plan__c` (and not native `AccountPlan`)?

Architecture §2.1 offers a custom baseline; §0 prefers extending native. This slice uses the
**custom baseline deliberately** so it (a) deploys without depending on native Account Plans
licensing, and (b) lets `Whitespace_Cell__c` be a true **master-detail** child — which gives the
`Total_ARR__c` / `Headroom__c` roll-up summaries and parent-controlled sharing for free. The open
master-detail-to-native-`AccountPlan` decision (§12.5) is therefore **not** on the critical path
for this preview. Swapping to native later is a re-parent exercise, not a rebuild.

## Deploy to KJDEV (sandbox)

> Target the **KJDEV sandbox** only. Authenticate a CLI to it first:
> `sf org login web --alias KJDEV --instance-url https://test.salesforce.com`

```bash
# From repo root — deploys only this module (leaves existing Opportunity metadata untouched)
sf project deploy start \
  --source-dir force-app/main/default/objects/Account_Plan__c \
  --source-dir force-app/main/default/objects/Whitespace_Cell__c \
  --source-dir force-app/main/default/objects/Plan_Product_Family__c \
  --source-dir force-app/main/default/objects/Plan_Stakeholder__c \
  --source-dir force-app/main/default/objects/Plan_Objective__c \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/tabs \
  --source-dir force-app/main/default/applications \
  --source-dir force-app/main/default/permissionsets \
  --target-org KJDEV

# (equivalent, via manifest)
# sf project deploy start --manifest scripts/deploy/manifest-account-plans.xml --target-org KJDEV
```

## After deploy — 3 steps to see it

1. **Assign yourself the permission set**
   `sf org assign permset --name Account_Plan_Admin --target-org KJDEV`
2. **Seed the demo data** (Latham law-firm plan + Vodafone corporate plan, their cells, then stakeholders + objectives)
   ```bash
   sf apex run --file scripts/seed/seed_account_plans.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_stakeholders_objectives.apex --target-org KJDEV
   ```
3. **Drop the components onto the page** (one-time, ~30s): open any Account Plan record →
   gear ▸ **Edit Page** ▸ drag **White-Space Matrix**, **Stakeholder Heat-Map** and **Objectives Panel**
   onto the canvas ▸ **Save** ▸ **Activate** (set as Org Default for `Account_Plan__c`).

Then open the **Account Planning** app ▸ **Account Plans** tab ▸ open *Latham & Watkins LLP*
(law firm) or *Vodafone Group plc* (corporate). The matrix renders the colour-coded states,
segment-relevant columns (Advertising drops out for corporate), and the roll-ups populate.

## Notes / deliberate scope

- **Headroom roll-up** here is a simple SUM of `Expected_Revenue__c`; the gap-to-benchmark
  *allocation* logic (architecture §3/§5) is a later phase.
- **No generation service yet** — cells are seeded. `WhitespaceGenerationService` (§4) and the
  multi-source "owned" union (§3.1) come next, and need a CPQ-seeded sandbox.
- **Penetration is split** into `Family_Coverage_Pct__c` vs `Seat_Penetration_Pct__c` on purpose
  (resolves the naming collision flagged against §2.1/§3).
- Objectives (§2.4) and stakeholders (§2.5) are now included. Signals (`Plan_Signal__c`, §9),
  team/sharing (§2.6/§8), snapshots (§10) and the generation service (§4) are **not** in this slice yet.
