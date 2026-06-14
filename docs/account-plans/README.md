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
| Custom object | `Plan_Signal__c` | AI/detection signals (§9): `Signal_Type__c`, `Severity__c`, `Recommended_Action__c`, `Status__c` history. |
| Custom object | `Plan_Team_Member__c` | Layered ownership (§2.6): `User__c`, `Plan_Role__c`, lane `Product_Family__c`. |
| Apex | `AccountPlanController` | `getMatrix` / `getStakeholders` / `getObjectives` / `getSignals` / `getTeam` (cacheable). |
| Apex | `PlanSharingService` + `PlanTeamMemberTrigger` | Team-based sharing (§8): grants Edit via the `Plan_Team_Access__c` reason. |
| LWC | `whitespaceMatrix` | Colour-coded white-space grid. |
| LWC | `stakeholderMap` | Influence × sentiment relationship heat-map. |
| LWC | `objectivesPanel` | Objectives with progress bars. |
| LWC | `keySignals` | Open signals with severity + recommended action. |
| LWC | `planTeam` | Layered plan team by role. |
| FlexiPage | `Account_Plan_Workspace` | Record page that pre-arranges every component. |
| App / tabs | `Account_Planning` + 7 tabs | Navigation. |
| Permission set | `Account_Plan_Admin` | Object + field + tab + record-type + Apex access. |

> **Sharing note:** `Account_Plan__c` OWD is **Public Read Only** so the `__Share` object exists for
> Apex managed sharing; `Plan_Team_Member__c` rows elevate their user to **Edit** via the trigger.
> `Account_Plan_Admin` grants View/Modify All so admins are unaffected.

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
  --source-dir force-app/main/default/objects/Plan_Signal__c \
  --source-dir force-app/main/default/objects/Plan_Team_Member__c \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/triggers \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/tabs \
  --source-dir force-app/main/default/applications \
  --source-dir force-app/main/default/flexipages \
  --source-dir force-app/main/default/permissionsets \
  --target-org KJDEV

# (equivalent, via manifest)
# sf project deploy start --manifest scripts/deploy/manifest-account-plans.xml --target-org KJDEV
```

## After deploy — 3 steps to see it

1. **Assign yourself the permission set**
   `sf org assign permset --name Account_Plan_Admin --target-org KJDEV`
2. **Seed the demo data** (plans + cells, then stakeholders + objectives, then signals + team)
   ```bash
   sf apex run --file scripts/seed/seed_account_plans.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_stakeholders_objectives.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_signals_team.apex --target-org KJDEV
   ```
3. **Activate the Workspace page** (one-time): open any Account Plan record →
   gear ▸ **Edit Page** ▸ **Activate** ▸ **Assign as Org Default** for `Account_Plan__c`.
   (The `Account_Plan_Workspace` FlexiPage already arranges every component, so no dragging needed.)

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
- Objectives (§2.4), stakeholders (§2.5), signals (§9) and team-based sharing (§2.6/§8) are now
  included. The generation service (§4), gap-to-benchmark allocation (§3/§5), snapshots/QBR trend
  (§10) and CRMA heat maps (§9) are the remaining slices.
- **FlexiPage caveat:** `Account_Plan_Workspace` targets the standard record-page template. If your
  org rejects the template/region names on deploy, drop the FlexiPage from the manifest and arrange
  the (already-deployed) components manually via Edit Page — everything else is unaffected.
