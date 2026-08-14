# Scope — Brand-Aware Motion on the Pardot Form Completion door (Door 2)

**Status:** scoping only (no code). KJDEV build target; Pardot path validates only in a Pardot-connected org.
**Goal:** make the upsell / renewal / cross-sell intelligence that Door 1 (the SDR cockpit) produces also available on **Pardot Form Completions**, so motion is known at *capture* — for routing, prioritisation, and (optionally) auto-created opportunities.

---

## 1. Where things stand today

| Piece | Door 1 — SDR cockpit | Door 2 — Pardot form |
|---|---|---|
| Entry | `smartConvert` LWC → `SmartConvertController.getMatch` | `Pardot_Smart_Resolve` flow (record-triggered on `Pardot_Form_Completion__c` create) |
| Firm/office match | ✅ `LeadMatchSelectService` | ✅ `LeadMatchSelectService` |
| **Brand customer status** | ✅ `BrandCustomerStatus.forFirm` | ❌ not called |
| **Motion (upsell/renewal/cross-sell)** | ✅ `SmartConvertController.classifyMotion` | ❌ not computed |
| Opportunity create + typing | ✅ at convert | ❌ |
| Output | converts + stamps telemetry | stamps `Account_Lead__c` only (pre-resolves the firm) |

**So the brand-aware work is Door-1 only.** The Pardot door just pre-resolves the account so the SDR's eventual cockpit convert is one-click — at which point the motion is computed normally. Nothing is *broken*; the intelligence simply isn't surfaced at form-capture time.

---

## 2. What it would take

### 2a. Extract the motion brain into a shared service (prereq) — ✅ DONE
`SalesMotionService` now exists (door-agnostic): `assess(firmId, canonicalBrand)` and `assessFromSource(firmId, lexologyProduct, almInterest, formBrand)` return `{brand, brandStatus, brandCustomer, familyCustomer, brandFamily, knownAccount, motion, renewalDate}`. Door 1 (`SmartConvertController` — both the preview banner AND the convert stamp) now calls it, so the two can no longer drift. It also ships an `@InvocableMethod` **"Assess Sales Motion"** (`category = Smart Convert`) taking `{firmId, formBrand, lexologyProduct, almInterest}` → motion fields, so **the Pardot flow can call it directly with no new Apex.** Deployed to KJDEV, tests green.

### 2b. Brand from the form
`BrandCustomerStatus.resolveLeadBrand(lexologyProduct, almInterest, **formBrand**)` already takes a form-brand third arg (passed `null` today). Door 2 would pass `Pardot_Form_Completion__c.Brand__c`.
- **⚠ Vocabulary audit required:** the form `Brand__c` picklist values must match `Brand_Mapping__mdt.Source_Value__c`. Form values may differ from the Lead picklist (`Lexology_Product__c`) we mapped against. Action: pull the form's `Brand__c` values and reconcile / add mappings (`Source_Field__c = 'Form.Brand__c'`).

### 2c. Wire it into the Pardot flow
After `Pardot_Smart_Resolve` resolves the firm, call an `@InvocableMethod` wrapper on `SalesMotionService` (flow → invocable) and stamp the result. New fields on `Pardot_Form_Completion__c` (or the linked `Account_Lead`): `Opportunity_Motion__c`, `Brand_Customer_Status__c`, `Renewal_Date__c`, `Brand_Family__c`. Mirror FLS on the integration/Pardot profile.

### 2d. Decide the behaviour (the real product question)
- **Inform only** (recommended first step): stamp motion + customer status on the form so routing/scoring/reps can use it. No auto-convert. Low risk.
- **Auto-act:** if forms can auto-convert or auto-create opps, the motion must drive opp `Type`/naming server-side (reuse the same `prefillOpportunity` mapping). Higher risk — needs the duplicate/contact-role guards the cockpit has.

---

## 3. Known constraints / risks
- **Untestable in KJDEV.** Pardot source fields (`Email__c`, `Company__c`, `Country__c`, `Brand__c`) are non-writable (Pardot-managed) and there's no Pardot integration in the sandbox → must validate in a **Pardot-connected** org (Full/UAT). `Pardot_Smart_Resolve` deploys as **Draft**.
- **`Country__c` is a country *name*, not ISO** → office *location* ranking is weak on the Pardot path (firm still resolves by domain; office falls to the opp tiebreaker). Optional: add a name→ISO map.
- **Same match-key dependency as Door 1:** `Account.Match_Domain__c` must be deployed + backfilled in prod first, or nothing resolves.

---

## 4. Suggested phasing
1. ~~**Prereq:** extract `SalesMotionService`~~ — ✅ **done** (shared service + `@InvocableMethod`, no behaviour change, tests green).
2. **Audit:** reconcile form `Brand__c` values ↔ `Brand_Mapping` source values. _S_
3. **Phase 1 (inform-only):** call the existing invocable from `Pardot_Smart_Resolve` after firm resolution + add 4 stamp fields; validate in a Pardot-connected org. _S–M_ (smaller now the brain exists).
   - ⚠ **Bulkify first:** `assessInvocable` is single-record oriented today (per-firm aggregate queries → SOQL-in-loop). Either guarantee the flow fires per-record, or bulkify `BrandCustomerStatus.forFirm` to take a `Set<firmId>` and resolve statuses in one pass, before any high-volume form batch hits it.
4. **Phase 2 (optional auto-act):** motion-driven opp creation with dedup/contact-role guards. _M–L_

**Recommendation:** do the refactor (1) opportunistically with the Door-1 work, then treat Door 2 as its own validated phase **after** the match-key backfill is live in prod. Don't couple it to the Door-1 go-live.
