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
| Apex | `WhitespaceAllocationService` | Gap-to-benchmark headroom engine (§3/§5): allocates `Expected_Revenue__c` across white-space cells. Apex / Flow (`@InvocableMethod`) / LWC. |
| Custom fields | `Plan_Product_Family__c.Benchmark_ARR_Per_Seat_{Law_Firm,Corporate}__c` | Per-seat benchmark inputs (segment-aware) that drive the gap calc. |
| Custom field | `Account_Plan__c.Account__c` | Anchors the plan to the firm's ultimate-parent Account (firm grain). |
| Custom field | `Whitespace_Cell__c.Office_Account__c` | Links a law-firm node to its real office Account (child via `Ultimate_Account__c`). |
| CMDT | `Plan_Benchmark_Setting__mdt` | Tier multipliers (`T1`/`T2`/`T3`) scaling the benchmark ceiling. Code defaults apply if absent. |
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

### Firm grain — plans and nodes tie to real Accounts

The plan is **firm-grained**. `Account_Plan__c.Account__c` ("Account (Plan Node)") anchors the plan to
the firm's **ultimate-parent Account** (the `Account.Ultimate_Account__c` grain used by the Am Law
whitespace report and the Office Activity Timeline), and `Parent_Plan__c` models enterprise→regional
plan hierarchy. On the white-space matrix, `Whitespace_Cell__c.Office_Account__c` links each law-firm
node to the **real office Account** under that firm (a child via `Ultimate_Account__c`) — so the matrix
rows are live CRM accounts, ARR/entitlements can later be sourced from them (the §4 generation service),
and the node label is a click-through. Corporate plans use practice-function nodes, which carry **no**
office Account. The seed anchors the demo law plan to **Globex Legal (DEMO)** (offices London /
Manchester / New York) and the corporate plan to **Demo Corp Alpha**.

> **Related list:** to see plans from the firm's Account page, add the **Account Plans** related list
> once via the Account page layout (Setup ▸ Object Manager ▸ Account ▸ Page Layouts ▸ drag *Account
> Plans* into Related Lists). It can't be deployed as standalone metadata.

### Headroom — gap-to-benchmark engine (§3 / §5)

`WhitespaceAllocationService` turns `Headroom__c` from a seeded placeholder into computed gap math.
For each plan × product family:

```
benchmark = benchmarkPerSeat(family, segment) × SoW_Denominator__c × tierMultiplier(Plan_Tier__c)
gap       = max(0, benchmark − owned ARR for that family)
```

The family `gap` is **allocated** across that family's *addressable* cells — the white-space states
`White_Space` / `Candidate` / `Win_Back` / `No_Engagement` — weighted by node size (the node's owned
ARR plus the plan average, so a wholly-greenfield node still draws a baseline share). The rounding
remainder is pinned to the largest-weight cell so the parts sum **exactly** to the gap. Held cells
(`Owned_Healthy` / `In_Renewal` / `Booked`) and `NA` cells are zeroed. Writing the cells lets the
existing `Headroom__c` / `Total_ARR__c` roll-ups reflect reality; `Family_Coverage_Pct__c` is
recomputed (present cells ÷ applicable cells). The pass is **idempotent** — re-running changes nothing.

- **Inputs** live on `Plan_Product_Family__c` (per-seat benchmark, segment-aware) and the
  `Plan_Benchmark_Setting__mdt` tier multipliers (`T1`=1.0, `T2`=0.85, `T3`=0.7; code defaults if absent).
- **Triggers:** Apex `WhitespaceAllocationService.allocate(Set<Id>)`, the `@InvocableMethod` for Flow,
  or the **Recalculate headroom** button on the White-Space Matrix (`AccountPlanController.recalcHeadroom`).
- **Out of scope here:** plan-level `Seat_Penetration_Pct__c` is left untouched (it means *seats sold ÷
  denominator*, which needs a seat-count source we don't yet have); and a family with a positive gap but
  **no** addressable cell leaves that gap unplaced by design.

### CRM Analytics — portfolio white-space heat map (§9)

A CRM Analytics heat map of **Headroom by Firm × Product Family** across the whole book, complementing
the per-plan matrix LWC. Built natively in CRMA (both KJDEV and prod have CRM Analytics Plus):

| Asset | Where | Purpose |
|---|---|---|
| App | `Account_Plans_Whitespace` (`wave/Account_Plans_Whitespace.wapp-meta.xml`) | Container app/folder. |
| Dataset builder | `scripts/seed/build_whitespace_crma_dataset.apex` | Apex External-Data uploader → `Whitespace_Headroom` dataset (denormalized: Firm/Plan/Segment/Tier/Family/Node/State/ARR/Headroom). Re-runnable. |
| Dashboard | `Whitespace_Headroom_Heatmap` (`wave/Whitespace_Headroom_Heatmap.wdash`) | `matrix` heat map, darker = more headroom. |

```bash
# After deploying wave/ + running the seeds, build/refresh the dataset:
sf apex run --file scripts/seed/build_whitespace_crma_dataset.apex --target-org KJDEV
```

> **Gotchas:** CRMA presence can't be detected via SOQL on `WaveDataset` (not SOQL-exposed) — use the
> Wave REST API (`/services/data/vXX/wave/datasets`). The data-sync job runs as the **Analytics
> integration user**; if it's frozen the job fails with *"the integration user is frozen"* — unfreeze
> it in Setup ▸ Users. External-data metadata needs `fullyQualifiedName` per field; `aggregateflex`
> dashboard steps need the stringified `query` form; dashboard pages need a `name`.

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
  --source-dir force-app/main/default/objects/Plan_Benchmark_Setting__mdt \
  --source-dir force-app/main/default/customMetadata \
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
2. **Seed the demo data** (plans + cells, then stakeholders + objectives, then signals + team,
   then benchmarks + headroom allocation)
   ```bash
   sf apex run --file scripts/seed/seed_account_plans.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_stakeholders_objectives.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_signals_team.apex --target-org KJDEV
   sf apex run --file scripts/seed/seed_benchmarks.apex --target-org KJDEV
   ```
3. **Activate the Workspace page** (one-time): open any Account Plan record →
   gear ▸ **Edit Page** ▸ **Activate** ▸ **Assign as Org Default** for `Account_Plan__c`.
   (The `Account_Plan_Workspace` FlexiPage already arranges every component, so no dragging needed.)

Then open the **Account Planning** app ▸ **Account Plans** tab ▸ open *Globex Legal (DEMO) - Account
Plan* (law firm) or *Demo Corp Alpha - Legal & Compliance* (corporate). The matrix renders the
colour-coded states, segment-relevant columns (Advertising drops out for corporate), and the
roll-ups populate. On the law-firm plan each node row links to its real **office Account** (Globex
London / Manchester / New York); the plan itself is anchored to the firm via `Account__c`.

## Notes / deliberate scope

- **Headroom is now computed**, not seeded — `WhitespaceAllocationService` allocates
  `Expected_Revenue__c` per cell from the gap-to-benchmark math (§3/§5); the `Headroom__c` roll-up
  reflects it. See *Headroom — gap-to-benchmark engine* above.
- **Generation service (§4) — first phase shipped.** `WhitespaceGenerationService.generate(planIds)`
  regenerates cells from the firm's **owned entitlement union** (Phase 1 = won Opportunities + line
  items; extensible to CPQ subscriptions + contracts), maps product→family via `CPQ_Family_Mapping__c`,
  links each node to its office Account, and chains the allocation engine so headroom recomputes.
  Invocable/Apex-callable; verified against the live Globex firm structure. `scripts/seed/seed_owned_opps.apex`
  seeds demo ownership (won Opps on the Globex offices) — note Product creation needs a valid
  record-type-restricted `Reporting_Stream__c` value. Cells are no longer purely hand-seeded.
- **Penetration is split** into `Family_Coverage_Pct__c` vs `Seat_Penetration_Pct__c` on purpose
  (resolves the naming collision flagged against §2.1/§3). The engine recomputes `Family_Coverage_Pct__c`;
  `Seat_Penetration_Pct__c` is left to a future seat-count source.
- Objectives (§2.4), stakeholders (§2.5), signals (§9), team-based sharing (§2.6/§8), the
  gap-to-benchmark allocation (§3/§5), the CRMA portfolio heat map (§9) and the first generation
  service (§4) are now included. **Snapshots / QBR trend (§10)** is the remaining slice, plus
  extending the §4 owned union to CPQ subscriptions + contracts when a CPQ-seeded sandbox is available.
- **FlexiPage caveat:** `Account_Plan_Workspace` now contains **only the custom LWCs** (matrix +
  sidebar panels) so it deploys cleanly. KJDEV refused the design-time info for the standard
  `flexipage:highlightsPanel` / `flexipage:recordDetail` components on deploy, so those were dropped;
  re-add them (and the highlights/record-detail panels) via **Edit Page** if your org supports them.
  Each `<itemInstances>` must wrap exactly **one** component — packing several into one is the
  "Element componentInstance is duplicated" deploy error.
