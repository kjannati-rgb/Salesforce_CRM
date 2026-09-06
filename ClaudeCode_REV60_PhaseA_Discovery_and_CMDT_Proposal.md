# REV-60 — ALM Promo & Dispatch Code Automation
## Phase A: KJDEV Discovery Findings + CMDT Proposal (for review)

**Author:** Kamyar Jannati · **Date:** 26 June 2026
**Org verified:** KJDEV sandbox — `kamyar.jannati@lbresearch.com.kjdev`, System Administrator, Law Business Research (UK) Ltd. (`getUserInfo`, 26 Jun 06:41 BST)
**Status:** Discovery complete. **CMDT proposed — awaiting sign-off before any flow is built.** No metadata deployed.
**Reuses:** REV-71 ALM invoice-code engine (deployed to production 24 Jun 2026), live in this repo.

---

## 1. Sandbox field state — CONFIRMED (read-only, KJDEV)

Queried `FieldDefinition` for both fields on both objects. KJDEV matches the production discovery in the brief exactly:

| Object | Field | Label | KJDEV type | Action |
|---|---|---|---|---|
| `SBQQ__QuoteLine__c` | `Promo_Code__c` | Promo Code | **Text(255)** | ✅ OK |
| `SBQQ__QuoteLine__c` | `Dispatch_Method_Code__c` | Dispatch Method Code | **Text(18)** | ⚠️ **widen to Text(255)** before relying on sync |
| `OpportunityLineItem` | `Promo_Code__c` | ALM Promo Code | **Text(255)** | ✅ OK |
| `OpportunityLineItem` | `Dispatch_Method_Code__c` | ALM Dispatch Method Code | **Text(255)** | ✅ OK |

- Both fields exist on both objects in KJDEV with **identical API names** → CPQ native twin-field sync is the carrier (no field mapping config needed; same-API-name match auto-syncs).
- **The one asymmetry from the brief is real here too:** Quote Line `Dispatch_Method_Code__c` is Text(18) vs OLI Text(255). First Phase-A action = widen the Quote Line field to Text(255). (Text length increase is non-destructive and safe.)
- Neither twin field is currently in the local repo `force-app` tree — they live only in the org. We will retrieve them into source control as part of Phase A so the widen + any layout work is tracked.

### 1.1 Sync behaviour — confirmed mechanism + known sandbox limitation

From the **deployed REV-71 Layer 1 flow** (`Quote_ALM_Code_Stamp`, in-repo description, validated 12 Jun 2026):
> *"CPQ's twin-field sync carries codes on OLI creation but suppresses re-entrant sync for QL updates made inside its own save transaction, so without this section stamped codes would lag one save behind on existing OLIs."*

**Implications REV-60 inherits directly:**
1. Same-API-name twin fields **do** sync Quote Line → OLI **on OLI creation** (ordering/contract).
2. **Updates to an existing OLI lag one save** — CPQ suppresses re-entrant sync inside its own transaction.
3. REV-71's fix: when the quote is **Primary**, Layer 1 also reconciles the Opportunity's OLIs directly (same derivation). **REV-60 reuses this exact technique** rather than trusting CPQ sync alone.

**Known KJDEV limitation (from REV-71):** the CPQ calculation/calc-service auth in this sandbox is expired, which blocks full live quote calc/sync testing. Phase A is therefore validated via (a) the field-state confirmation above, (b) the in-flow OLI reconciliation (not CPQ-sync-dependent), and (c) the Apex regression suite. Full QL→OLI sync round-trip is a FULLUAT/UAT step.

---

## 2. REV-71 ALM classification — CONFIRMED (reuse target)

REV-71 drives all product scope from `ALM_Code_Setting__mdt` (no product codes hardcoded in flow). The classification in the repo today:

### 2.1 Bundle Family records (the ALM anchor set)
| DeveloperName | Anchor `ProductCode`(s) | TCV_Code |
|---|---|---|
| Family_Law_com_Premium | `LAWM` | 1 |
| Family_GLL | `GLBM`; `GLBM - Team Membership`; `GLBM - Individual Membership` | 2 |
| Family_Law_com_International | `LWKM` | 3 |

### 2.2 Bundle Parent records (child-exclusion / bundle parents)
`GLBM`, `Law.com Premium Bundle`, `Law.com Pro`, `Law.com International Bundle`, `Mid Market Pro Bundle`, `LAWM + (LARM OR LRCM OR LRLM)` (Radar), `LAWM OR Any Regional + WEB` (VerdictSearch).

### 2.3 Control record
`Layer_1_Active = true`, `Layer_2_Active = true`, `Use_Net_Total_Price = true` (live in KJDEV).

### 2.4 Reusable engine pattern (extracted from the two deployed flows)
| Mechanism | REV-71 implementation | REV-60 reuse |
|---|---|---|
| CMDT-driven config | `ALM_Code_Setting__mdt` (Control + Family + Parent rows) | new `ALM_Code_Map__mdt` + `ALM_Code_Engine_Settings__mdt` (§3) |
| Kill switches | `Get_Control` → `D_Layer1/2_Active` decision gates | same gate pattern, new Settings fields |
| Org bypass | Layer 2: `$Setup.Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` | reuse identical bypass |
| Fault logging | subflow **`PFC_Log_Fault`** (inputs: `inputContext`, `inputErrorDescription`, `inputFlowName`, `inputRecordName`) on every `faultConnector` + a no-anchor visibility row | reuse the same subflow, same 4 inputs |
| Child exclusion | QL: `SBQQ__RequiredBy__c` OR `SBQQ__ProductOption__c` set → child; OLI: `SBQQ__ParentID__c` set → child | reuse identical detection |
| Run mode | `SystemModeWithoutSharing` | same |
| Write guard | idempotent: write only when derived ≠ current; "clear mode" only clears values matching configured codes | **adapted — see §4 (write-when-blank/ALM-owned), the key REV-60 difference** |
| Layer 1 dispatch | autolaunched `Quote_ALM_Code_Stamp`, invoked as a subflow from `Quote_AfterSave_MasterFlow` with `in_Quote` | **reuse** — new subflow `Quote_ALM_PromoDispatch_Stamp` chained in the same orchestrator (§5-D1 resolved) |
| Layer 2 | record-triggered **on Opportunity** (after-save, `triggerOrder` 1000), single actor per opp — NOT on OLI | **reuse** — Opportunity-triggered (§5-D2 resolved) |

> **Note — two REV-71 realities that differ from the REV-60 brief wording:**
> - REV-71 Layer 2 is an **Opportunity-triggered** flow, not an OLI-triggered one (the spec's line-level OLI design was deliberately replaced with a single-actor-per-opportunity flow to avoid OLI trigger storms).
> - REV-71 Layer 1 is **routed through the master flow**, not a direct QuoteLine record-trigger.
> These are the two architecture decisions to confirm for REV-60 (§5).

### 2.5 Scope gap to confirm: **NYLJ**
The brief names four core ALM codes (LAWM, LWKM, GLBM, **NYLJ**). REV-71's classification maps only **LAWM / LWKM / GLBM** (NYLJ was never needed for TCV consolidation). REV-60's ALM-scope set must therefore be **stated explicitly** (it is broader than REV-71's anchor set). Proposal seeds NYLJ into the ALM scope list pending confirmation (§3.2, §6).

---

## 3. Proposed CMDT (per brief §5) — FOR REVIEW

Two new CMDTs, kept separate from REV-71's `ALM_Code_Setting__mdt` (so the deployed TCV config is never touched). Conventions mirror REV-71: `DeveloperControlled`, semicolon lists, public visibility, xsi/xsd namespaces on records. **All rows ship empty of mapping values and switched OFF** (scaffold only).

### 3.1 `ALM_Code_Map__mdt` — one row per determinant key
| Field API | Type | Purpose |
|---|---|---|
| `Match_Key__c` | Text(255) | The determinant value the engine matches the line's computed key against. Exact determinant per §7.1 (ProductCode, or ProductCode + Region/Edition). **Empty in scaffold.** |
| `Base_Promo_Code__c` | Text(50) | DBReg base promo, e.g. `!SJSI`, `MSHP`, `!AMLW`. **Empty in scaffold.** |
| `Dispatch_Code__c` | Text(50) | Standardised target dispatch code, e.g. `OL`, `ME`, `ON`. **Empty in scaffold.** |
| `Apply_Year_Suffix__c` | Checkbox (default **true**) | Whether `Y2/Y3/Y4` composes onto this base (some bases are fixed/un-suffixed). |
| `Z_Eligible__c` | Checkbox (default **false**) | Whether this base can take the `+Z` modifier (AND-ed with the global Z trigger, §3.2). |
| `Active__c` | Checkbox (default **true**) | **Per-row kill switch** (brief §5). |
| `Notes__c` | Text(255) | Config provenance — which row of the *Codes – Integra and DBReg* sheet this came from. |

### 3.2 `ALM_Code_Engine_Settings__mdt` — single `Control` row (engine config + master switches)
| Field API | Type | Scaffold default | Purpose |
|---|---|---|---|
| `Master_Active__c` | Checkbox | **false** | Global master kill switch — engine inert until flipped on. |
| `Layer_1_Active__c` | Checkbox | **false** | Layer 1 (Quote Line) kill switch. |
| `Layer_2_Active__c` | Checkbox | **false** | Layer 2 (safety net) kill switch. |
| `ALM_Product_Codes__c` | Text(255) | `LAWM;LWKM;GLBM;GLBM - Team Membership;GLBM - Individual Membership;NYLJ` *(NYLJ pending §2.5)* | **ALM-scoping gate** — engine only acts on lines whose ProductCode is in this set. Reuses REV-71 anchor set. |
| `Year_Suffix_Enabled__c` | Checkbox | **true** | Global toggle for year-suffix composition (§7.3). |
| `Z_Trigger_Enabled__c` | Checkbox | **false** | Global toggle for `+Z` logic (§7.4). |
| `Z_Trigger_Product_Codes__c` | Text(255) | *(empty)* | Semicolon list of ProductCodes that trigger `+Z` (e.g. Mid Market Pro). AND-ed with row `Z_Eligible__c`. |
| `Determinant_Field_API__c` | Text(255) | *(empty)* | **Documentation** — the quote-line field carrying the base determinant (§7.1). Wired in-flow once confirmed (Flow can't reference a field by dynamic name). |
| `Contract_Year_Field_API__c` | Text(255) | *(empty)* | **Documentation** — source of the contract-year index (§7.3). Wired in-flow. |

---

## 4. Write guard (the critical REV-60 difference) — FOR REVIEW

Unlike REV-71 (whose `Full_Contract_Value__c` is an ALM-only field with no legacy values), the REV-60 target fields hold the **entire legacy LBR vocabulary** (tens of thousands of rows). The guard must be strictly additive:

- **Scope gate:** act only if `ProductCode ∈ ALM_Product_Codes__c` **and** the line is not a bundle child (REV-71 child detection reused).
- **Promo write-when-blank/ALM-owned:** write the derived `base + yearSfx + zMod` when the target is **blank**, OR when the target is **ALM-owned** — defined as: *strip a trailing `Z` and a `Y2/Y3/Y4` suffix from the current value; if the remaining base matches a configured `Base_Promo_Code__c`, it is engine-authored and safe to refresh.* Never overwrite a value whose stripped base is not a configured ALM base.
- **Dispatch write-when-blank/ALM-owned:** write the resolved `Dispatch_Code__c` when target is **blank** OR target ∈ the set of configured `Dispatch_Code__c` values. **Never write a `P*` (print) code to an ALM line**, and never overwrite an unknown legacy dispatch value.

This makes every legacy LBR code off-limits while still allowing the engine to fill blanks and refresh its own prior output.

---

## 5. Architecture decisions — RESOLVED (26 Jun)

- **D1 — Layer 1 trigger type → route through `Quote_AfterSave_MasterFlow` as an autolaunched subflow (REV-71 pattern).** This is the best-outcome / most-stable choice for a CPQ org, confirmed against the live orchestrator:
  - `Quote_AfterSave_MasterFlow` is the org's **single after-save actor on `SBQQ__Quote__c`** (org-bypass-gated), already invoking REV-71's `Quote_ALM_Code_Stamp` (`in_Quote = $Record`) behind a `D_ALM_Code_Relevant` change gate.
  - A per-`SBQQ__QuoteLine__c` record-triggered flow (before or after save) would fire **on every line, on every CPQ recalculation save** — the classic CPQ governor/recursion trap. The REV-71 team deliberately avoided it; we do too.
  - REV-60 adds a new autolaunched subflow `Quote_ALM_PromoDispatch_Stamp` (`in_Quote`) chained after `SF_ALM_Code_Stamp` under the existing relevance gate: **fires once per quote calculation**, controlled ordering next to REV-71, preserves `PFC_Log_Fault` DML logging, and still produces per-line results by looping the quote's lines internally. One orchestrator, one trigger per object — long-term maintainable.
- **D2 — Layer 2 object → Opportunity-triggered** (match REV-71; single actor per opp, avoids OLI trigger storms). ✅
- **D3 — NYLJ → seed into `ALM_Product_Codes__c` now, flag for Cayla/Team Brady confirmation.** ✅
- **D4 — Write guard → blank-or-ALM-owned** (§4 base-strip test). ✅

None of these change the proposed CMDT (§3).

---

## 6. Phase A build order (once CMDT is approved)
1. Retrieve both twin fields into source control; **widen** Quote Line `Dispatch_Method_Code__c` → Text(255).
2. Deploy `ALM_Code_Map__mdt` + `ALM_Code_Engine_Settings__mdt` (+ one empty `Control` Settings row, all switches OFF).
3. Build Layer 1 (per D1) + Layer 2 (per D2): ALM scope gate, child exclusion, base+suffix+Z composition (structure only), write-when-blank/ALM-owned guard, kill switches, `PFC_Log_Fault` wiring, primary-quote OLI reconciliation.
4. Apex regression suite mirroring `REV71_ALMCodeFlow_Test` coverage + scenario matrix (per-product, multi-year suffix, +Z, blank-field fill, legacy-untouched, P*-never, child-excluded).
5. Activation-order + rollback note. Demo-ready in KJDEV. **No auto-deploy.**

**Activation order (documented now, executed last):** deploy fields → deploy CMDT (OFF) → seed `ALM_Code_Map` rows (Phase B, post §7.1) → deploy flows (inactive/OFF) → flip `Layer_1_Active`/`Layer_2_Active`/`Master_Active`.
**Rollback:** flip the relevant switch to false (instant, no redeploy); or deactivate the flow version.

---

## 7. Late finding (26 Jun) — existing CPQ Validation Product Rules force manual entry (PROD only)

Confirmed in **production** (absent in KJDEV — sandbox drift). Active CPQ Product Rules (`SBQQ__Type__c = Validation`) currently **block quote save** when these fields are blank:

| Rule | Tested field (Quote Line) | Fires when | Error |
|---|---|---|---|
| **Promo Code Required - Non bundle products** | `Promo_Code__c` | equals null (blank) | "You must provide a Promo code for all invoiced items" |
| **Law.com Benefitting Group - Restrict Sales Rep EMEA** | `Dispatch_Method_Code__c` | equals null | "Please add Dispatch Code as \"BE\"" |
| **Law.com Benefitting Group - Restrict Sales Rep APAC** | `Dispatch_Method_Code__c` | equals null | "Please add Dispatch Code as \"BA\"" |

(Plus `LBR - Finance Code Required` / `Finance Code Required - Commissioned Content Slot` — finance-code, REV-71-adjacent, separate.)

**Two implications:**

1. **Timing collision.** CPQ Validation Product Rules evaluate at **Save / Calculate**. REV-60 Layer 1 stamps in the **after-save** master flow — *after* the validation runs — so reps would still be blocked. Resolution options (rollout decision, Cayla / Team Brady): (a) stamp during Calculate via a CPQ **Price Rule** instead of/alongside the after-save flow; (b) **scope down or retire** these manual-entry validations for in-scope ALM products once REV-60 fills the field reliably — their entire purpose is to force the manual entry REV-60 automates; (c) make the validations conditional on "not an ALM-automated product." Most likely: REV-60 going live is precisely what lets (b) happen.
2. **Determinant — decoded from the full rule scope (26 Jun).** Two solid facts, one still-open:
   - **ALM scope = `Quote Line.Division__c = 'ALM'`** (+ non-bundle, `ProductFamily ≠ Subs - Memberships`, non-Amendment). The org's existing ALM marker — REV-60 scope should align to it.
   - **Dispatch BE/BA is driven by the quote's `SBQQ__SalesRep__c`** (hardcoded rep user IDs) for `ProductName = 'Law.com'` — rep/region-specific and brittle, **not** a clean line-level "Benefitting Group" field.
   - **§7.1 still open:** the Promo rule enforces **presence only**, not value — it does not reveal what selects the base promo.

   Full analysis + the timing decision are in **`ClaudeCode_REV60_Validation_Collision_Memo.md`** (for Cayla / Team Brady).

**Action:** this is a new §7-adjacent gate — REV-60's value is not just convenience; it is what makes the mandatory Promo/Dispatch validations satisfiable automatically (or retirable). Confirm the timing strategy before production rollout.

---

## 8. §7.1 determinant hunt — ANSWERED (negative) (26 Jun, PROD data)

Profiled all **2,263 Law.com (LAWM) quote lines** that carry a promo code (74 distinct codes) against every plausible determinant field.

**Result: there is no populated, varying quote-line field that determines the base promo.**

- **Law.com is a single `Product2`** (every one of the 74 codes maps to `prods = 1`) carrying ~20 base families: `!SJSI` (~1,400 lines across `Y1–Y4`/`Z`/`Q` variants), `!AMLW` (~345), `!NLJO`, `!GLBL`, `!SREN` (renewal), `ISIJ`, `A611` …
- `Brand__c`, `Reporting_Stream__c`, `SBQQ__ProductName__c`, `Publication_Title__c` are all the **constant value "Law.com"** (the last two are formulas off the product) → cannot vary with the base.
- `Benefitting_Group__c`, `Edition__c`, `Region_Tier__c`, `Chapter_Region__c`, `Geography__c`, `Law_com_BG_Group/country__c` are **~100% NULL** on historical lines (the Law.com BG fields populated on just **6 of 2,263**).

**Implication — this reframes §7.1.** The base promo is entered **by hand**, not derived from any captured input — which is exactly *why* the validation rule has to force manual entry. **"Based on existing inputs" does not hold for Law.com.** To automate the base, the org must **first introduce a structured input** (a rep-selected picklist — e.g. repurpose `Benefitting_Group__c` / `Law_com_BG_Group__c`, or a new "Offer / Promo Family" picklist) that maps to the base, then seed the CMDT from it. The codes look like marketing **campaign/offer** codes (`!`-prefixed; `!SREN` = renewal) — consistent with the brief's note that the mapping lives only in the *Codes – Integra and DBReg* sheet, not in Salesforce.

**What REV-60 can still automate now** (deterministic, needs no new input): the **year suffix**, the **+Z** modifier, and **dispatch standardisation**. Only the **base** is blocked — on a data-capture decision, not on engineering.

**§7.3 nuance found:** year 1 is *usually* unsuffixed (`!SJSI`, 608) but *sometimes* explicit `!SJSIY1` (40 lines) — confirm whether Y1 should be emitted or suppressed. There is also a `Q` infix variant (`!AMLWQ`, `!NLJOQ`, `!SJSIQ`) not in the original model — confirm its meaning.

---

## 9. Promo logic DECODED from the QSS sheet (26 Jun) — supersedes §8's "negative"

Cayla sent **"QSS Codes for Sales.xlsx"** (the rep reference) + **"Codes- Integra and DBReg 2.xlsx"**. These contain the full rule. §8's "no determinant" was because I profiled region/edition fields — **the real determinant is sales team + segment**, which those fields don't hold.

### 9.1 Composition rule (Promo Calculator tab) — richer than we modelled
```
Promo_Code = Base + Frequency + YearTerm + Modifier
  Base      = from the (Segment × Team × New/Renewal) lookup below
  Frequency = ""(annual) | M(monthly) | Q(quarterly) | H(semi-annual)   ← billing frequency
  YearTerm  = ""(year 1) | Y2 | Y3 | Y4 | Y5                            ← contract years (note: up to Y5)
  Modifier  = Z (Mid Market Pro bundle) | P (Law Premium bundle) | ""    ← bundle membership
```
e.g. `!SJSIQY3` = `!SJSI` + Q + Y3; `!NLJOY3Z` = `!NLJO` + (annual) + Y3 + Z.
**Engine corrections needed:** add the **Frequency** component (was missing); extend year to **Y5**; add the **P** (Law Premium) modifier alongside **Z**. `Q` = quarterly billing (confirmed).

### 9.2 Base determinant (Promo tab) = Segment × Sales Team × New/Renewal
The base is a **lookup**, not a free choice. Same Law.com product → different base by who sells it and to which segment:

| Segment (Prod/Group) | Sales Team/Leader | Base |
|---|---|---|
| AmLaw | Shawn | `!AMLW` |
| Global | Shawn | `!GLBL` |
| NLJ | Jessica/Shawn | `!NLJO` |
| Non-AmLaw | Shawn | `!SGRP` |
| Non-AmLaw | Jessica/Khris | `!SJSI` |
| Non-AmLaw | Brady | `!MCLG` |
| Non-AmLaw | Jessica (renewal) | `!SREN` |
| GLL | Khris/Shawn | `MSHP` |
| LawPro | Shawn | `!SGRPW` |
| (specific publications, monthly) | — | per-product, e.g. `LAWMO`, `TALMO`, `NYOMO` |

- **Sales Team/Leader** (Brady/Shawn/Jessica/Khris) → derivable from the **Opportunity Owner / rep's team** (same driver as the `BE`/`BA` dispatch rules, which key on `SBQQ__SalesRep__c`).
- **New vs Renewal** → derivable (quote/opp type; `!SREN` = renewal series).
- **Segment** (AmLaw / Non-AmLaw / Global / NLJ) → **RESOLVED (Kam, 26 Jun).** It's the **firm's ranking**, evaluated on the firm (`Account.Ultimate_Account__c`): `AmLaw ranking → AmLaw; else NLJ 500 → NLJ; else Global 200 → Global; else Non-AmLaw`. **Already a field:** `Account.Model_Segmentation__c` = `A`/`N`/`G`/`O` (matches the cascade; populated on ~7.7k ranked firms). Raw inputs also present if we'd rather compute it: `AmLaw_200_Account__c` (checkbox), `NLJ_Rank__c` (text). → **zero new rep input needed.**

### 9.3 Dispatch (Dispatch tab) = Product × Seat/Licence type — clean, seedable now
| Case | Dispatch |
|---|---|
| Online, 1 seat | `ON` |
| Online, site (5+ users) | `OS` |
| Online, enterprise | `OE` |
| Law.com Pro (firmwide) | `OL` |
| GLL / membership | `ME` |
| Print (incl. NYL print-only) | `PO` (+ regional `PB/PM/PP`) |
| E-newsletter / digital | `EN` / `DI` |
| Benefitting-group region overlay | `BE` (EMEA) / `BA` (APAC) |

Seat/licence count is on the quote → dispatch is largely derivable + standardisable. ALM is **never `P*` print** except NYL — guardrail holds.

### 9.4 Other tabs
- **Bundle Products / modifiers:** `Z` = Mid Market Pro, `P` = Law Premium Bundle — both detectable from the bundle parent (reuse REV-71 classification).
- **Integra/DBReg file:** Publication → Integra code (`LAWM`…) + DBReg base (`PAR`…) + Radar **regional packages** (`LRREGIONNE/MA/SA/…` by US region). This is the **Integra export side** (§7.6) — a different code layer from the QSS `Promo_Code__c`; relevant for the Radar regional products and the export, not the Law.com base.

### 9.5 Net effect on §7.1
Flipped from "no determinant" to **"determinant is a documented lookup on Segment × Team × New/Renewal × Frequency × Term."** Team, new/renewal, frequency, term, the Z/P bundle flags, **and segment** (§9.2, `Model_Segmentation__c`) are **all derivable from existing Salesforce data**. **§7.1 is fully resolved — the base is 100% derivable with no new rep entry.** Remaining work is engineering + sign-off: update the engine to the real composition (Frequency + Y5 + P), seed the CMDT (base lookup + dispatch), confirm the team→base rows + year-1/Q with Brady/Willie, decide the validation-timing approach, then UAT.
