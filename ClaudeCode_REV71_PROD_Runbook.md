# REV-71 — Production deployment runbook (LBR_PROD)

Deploy target: `LBR_PROD` (**production**). Source: the `force-app` tree in this repo,
built and verified in KJDEV (§6 matrix 22/22, regression suite `REV71_ALMCodeFlow_Test` 11/11).
Spec: `REV-71_ALM_Invoice_Code_Automation_Build_Spec.md`. Per spec §10: **no deploy without
demo to Cayla/stakeholders and explicit sign-off.**

**What ships:** twin field `SBQQ__QuoteLine__c.Full_Contract_Value__c`; `ALM_Code_Setting__mdt`
(object + 7 fields + 11 records); `Quote_ALM_Code_Stamp` (Layer 1 engine subflow);
a new version of `Quote_AfterSave_MasterFlow` (3-element hook); `Opp_ALM_Code_AfterSave`
(Layer 2); `REV71_ALMCodeFlow_Test`. Fault logging reuses the existing `PFC_Log_Fault`.

> ⚠️ **Two prod-specific facts shape this runbook:**
> 1. **LBR_PROD deploys flows as Draft** ("deploy flows as active" is OFF) — flows must be
>    activated manually AFTER deploy, in the order below. The currently-active master flow
>    version keeps running untouched until step 6 — that activation IS the go-live moment.
> 2. **Prod has pre-existing unrelated red tests** — Apex must deploy with
>    `RunSpecifiedTests` (never `RunLocalTests`).

---

## ★ UPDATE — Law.com Pro / Mid Market exemption (built 30 Jun 2026)

**Ruling (Brady Blevins, 30 Jun 2026):** Law.com Pro and Mid Market Pro bundles do **not**
carry a TCV code — they must be **blank**. Signals (existing fields, populated manually
today, REV-60-automated later): **Law.com Pro → `Dispatch_Method_Code__c = 'OL'`**;
**Mid Market Pro → `Promo_Code__c` ends in `Z`**.

**What changed:** a deal-level exemption was added to **both** engine flows
(`Quote_ALM_Code_Stamp` Layer 1, `Opp_ALM_Code_AfterSave` Layer 2): a `Get_ExemptLines`
lookup (`filterLogic 1 AND (2 OR 3)`: record-match AND (Dispatch=OL OR Promo EndsWith Z))
feeds a new `D_ProExempt` decision that, when any exempt line exists, routes to the existing
clear-mode path → **all lines blank + any stale code cleared**. Checked *before* the
single-product / family-derivation logic, so it overrides derivation. The master flow is
**unchanged** (the hook still calls `Quote_ALM_Code_Stamp` by name → picks up the new active
version automatically). **No CMDT/field/master changes** — only the two flow versions + test.

**Validated:** KJDEV `REV71_ALMCodeFlow_Test` **14/14** (4 new exemption methods incl. flat
LAWM+LWKM+OL → blank, promo-Z → blank, exempt-clears-stale-code) + FULLUAT redeploy. The
`EndsWith` operator, `1 AND (2 OR 3)` filter logic and `IsNull`-on-Get decision are all
accepted metadata (deployed clean to KJDEV + FULLUAT).

**Prod deploy (engine flows arrive Draft → activate; test class separate):**
```bash
# A. Pre-flight (read-only): confirm the two signal fields exist on BOTH objects in prod
sf data query -o LBR_PROD -q "SELECT QualifiedApiName, EntityDefinition.QualifiedApiName FROM FieldDefinition WHERE QualifiedApiName IN ('Dispatch_Method_Code__c','Promo_Code__c') AND EntityDefinition.QualifiedApiName IN ('SBQQ__QuoteLine__c','OpportunityLineItem')" -t
# note the CURRENT active versions (rollback target):
sf data query -o LBR_PROD -q "SELECT ApiName, ActiveVersionId FROM FlowDefinitionView WHERE ApiName IN ('Quote_ALM_Code_Stamp','Opp_ALM_Code_AfterSave')"

# B. Validate then deploy the two updated flows (NO Apex → no test gate; arrive Draft):
sf project deploy start -x manifest/rev71_prod_exemption_engine.xml -o LBR_PROD --dry-run
sf project deploy start -x manifest/rev71_prod_exemption_engine.xml -o LBR_PROD

# C. Activate the new versions — Quote_ALM_Code_Stamp FIRST (subflow), then Opp_ALM_Code_AfterSave
#    (Setup → Flows → Activate the newly deployed version, or via FlowDefinition metadata).

# D. Deploy the test class separately (post-activation; runs only REV-71 tests):
sf project deploy start -d force-app/main/default/classes/REV71_ALMCodeFlow_Test.cls \
  -l RunSpecifiedTests -t REV71_ALMCodeFlow_Test -o LBR_PROD
```
- [ ] Pre-flight: both signal fields present on QuoteLine + OLI (confirmed read-only 30 Jun).
- [ ] Flows deployed Draft; prior versions still active.
- [ ] New `Quote_ALM_Code_Stamp` activated, then `Opp_ALM_Code_AfterSave` activated.
- [ ] Test class redeploy green (14/14).
- [ ] Smoke: a real Law.com Pro (OL) deal saves with **blank** TCV; a normal multi-product
      deal still codes. Skadden (Q-197826) already corrected to blank.

**Rollback:** re-activate the prior versions captured in step A (instant), or flip the CMDT
`Layer 1/2 Active` switches off. No field/CMDT/master change to unwind.

> The exemption uses Brady's **signal** (dispatch/promo), not product mix — so it cannot
> distinguish a Law.com Pro package from a normal multi-product deal by SKUs (Willie's point,
> 30 Jun). A future dedicated bundle flag/parent is the cleaner long-term identifier; until
> then the signal is what's present on real flat-structured deals, and REV-60 will make it
> system-set.

---

## Readiness snapshot — validated against PROD 24 Jun 2026 (read-only)

**UAT: PASS.** Cayla Vichot ran 7 scenarios in FULLUAT (REV-71 ticket, 24 Jun):
S1 Int'l-higher → **3** ✅ · S2 reprice-flips → **1** ✅ · S3 GLL → **2** ✅ · S4 2-yr-all → **2** ✅ ·
S5 Law.com+NYLJ → **1** ✅ · S7 Law.com Pro bundle → **1** ✅. S6 (Mid Market Pro Bundle) could
not be tested — the bundle required Verdict Search to be selectable; Cayla confirmed this is a
**CPQ bundle-config issue, not the ALM-code logic, and not a deployment blocker.** Engine also
deployed + regression-green in FULLUAT (10/10) and verified firing on live data.

**Pre-flight (run 24 Jun, read-only against LBR_PROD):**
- ✅ Production confirmed (Law Business Research Ltd, IsSandbox=false).
- ✅ **`PFC_Log_Fault` EXISTS + active in prod → EXCLUDED from the package** (do NOT redeploy).
  FULLUAT lacked it and needed it shipped; prod does not — hence the prod manifest differs.
- ✅ `Flow_Log__c` exists; `ALM_Code_Setting__mdt` absent; OLI `Full_Contract_Value__c` exists;
  QL twin absent — all as expected.
- ✅ **MASTER-FLOW DRIFT CLEAN:** prod's live `Quote_AfterSave_MasterFlow` vs the repo's hooked
  version = **0 removals / 45 additions** (the REV-71 hook only). Deploy is purely additive.
- ℹ️ **923** coded OLI lines live (was ~872 at audit).

**Package: `manifest/rev71_prod_engine.xml`** (engine-only) — CMDT + twin field + 3 flows
(`Quote_ALM_Code_Stamp`, `Opp_ALM_Code_AfterSave`, `Quote_AfterSave_MasterFlow`).
**`PFC_Log_Fault` excluded** (already in prod) and **`REV71_ALMCodeFlow_Test` excluded** (see below).

> **⚠️ Validation finding (24 Jun, check-only vs PROD):** the original single-package validation
> (incl. the test class) FAILED — but **not a REV-71 defect**: (1) prod deploys flows as Draft, so
> during the bundled test run the engine is inactive → 8 behaviour asserts returned `null`; and
> (2) a pre-existing prod flow `Quote_BeforeSave_UpdateQuoteFields` faults on the test's quote insert.
> **Fix:** deploy the **engine-only** package (no Apex → no test gate; re-validated **23/23, 0 errors,
> 0 tests** = clean), activate the flows, then deploy the test class separately (§1b). The engine
> deploy is unaffected — the test class only matters for regression and can only pass post-activation.

**Still required before pressing deploy:**
- [ ] **Integra-owner confirmation** of which field Integra consumes — `Full_Contract_Value__c`
  (Number; where the engine writes and where the 923 codes already sit) vs the never-populated
  `ALM_Total_Contract_Value__c` (Text). Raised in REV-71 comment 640503; **still unconfirmed.**
- [ ] Sign-off acknowledges the VAR-tie → 1 (Brady) and single-product → blank (Cayla) rules.

**Separate prod change (NOT in this metadata package):** the CPQ Product Rule **"LBR - Finance
Code Required"** ALM exemption — advanced condition `1 AND 2 AND 3 AND 5` → `1 AND 2 AND 3 AND 4 AND 5`
(condition 4 = Quote Line `Division__c` ≠ `ALM`) — was applied in FULLUAT per Kam's 23 Jun decision.
Prod needs the **same manual edit** (Setup → CPQ → Product Rules; it's a data/config change, not metadata).

---

## 0. Pre-flight (read-only, re-run at deploy time)

```bash
# Confirm the target really is production
sf data query -o LBR_PROD -q "SELECT Name, IsSandbox FROM Organization"

# CPQ calculation service must be healthy (KJDEV's was expired post-refresh; prod should
# show recent Completed jobs and no auth errors)
sf data query -o LBR_PROD -q "SELECT Status, ExtendedStatus, COUNT(Id) c FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableCalculatorService' AND CreatedDate = LAST_N_DAYS:7 GROUP BY Status, ExtendedStatus"

# The write target and its current usage (expect ~872 coded lines / ~1,860 monetary)
sf data query -o LBR_PROD -q "SELECT COUNT(Id) c FROM OpportunityLineItem WHERE Full_Contract_Value__c IN (1,2,3)"

# No conflicting flow names / no REV-60 arrivals on the shared objects since the KJDEV audit
sf data query -o LBR_PROD -q "SELECT ApiName, IsActive, TriggerOrder FROM FlowDefinitionView WHERE TriggerObjectOrEvent.QualifiedApiName IN ('SBQQ__Quote__c','Opportunity') AND IsActive = true ORDER BY ApiName"

# Master flow drift check: retrieve prod's Quote_AfterSave_MasterFlow and diff against
# this repo's pre-edit version — if prod's master changed since the KJDEV copy, REBASE
# the 3-element hook onto prod's current version before deploying.
sf project retrieve start -m "Flow:Quote_AfterSave_MasterFlow" -o LBR_PROD --target-metadata-dir ./_prod_compare
```
- [ ] Production confirmed; calc service healthy.
- [ ] Master flow diff reconciled (the hook = 1 formula `frm_ALM_CodeRelevant`, 1 decision
      `D_ALM_Code_Relevant`, 1 subflow call `SF_ALM_Code_Stamp`, 1 connector from
      `Update_Generic_Information`).
- [ ] Cayla/stakeholder sign-off on file (spec §10) — including the §8-Q4 working assumption
      and the VAR-tie→family-1 assumption, both tagged in flow descriptions.
- [ ] Integra owner belt-and-braces confirmation noted (spec §8-Q1).

## 1. Field + CMDT + Apex  *(additive; flows deploy Draft in the same package — safe)*

One deploy, everything except nothing — flows arrive Draft so nothing behaves differently yet:

```bash
# ENGINE-ONLY package (no Apex). Deploys with NO test run — REV-71's engine is flows, no
# production Apex needs coverage. The test class is deployed SEPARATELY after activation
# (§1b) because it asserts LIVE engine behaviour and can only pass once the flows are active.
# (Validated check-only against PROD 24 Jun: 23/23 components, 0 errors, 0 tests.)

# Validate first (check-only):
sf project deploy start -x manifest/rev71_prod_engine.xml -o LBR_PROD --dry-run
# then the REAL deploy (drop --dry-run):
sf project deploy start -x manifest/rev71_prod_engine.xml -o LBR_PROD
```
- [ ] Validation green (incl. 11/11 tests), then real deploy green.
- [ ] Confirm flows arrived **Draft**: new `Quote_ALM_Code_Stamp` + `Opp_ALM_Code_AfterSave`
      inactive; master's ACTIVE version unchanged (prior version still live).

## 2. FLS on the twin field  *(metadata-deployed fields ship with no FLS)*

```bash
sf apex run -f scripts/rev71_mirror_fls_twin_field.apex -o LBR_PROD
```
Copies the OLI original's FieldPermissions onto the twin (idempotent; license-restricted
parents fail harmlessly — expect ~8 skips, same as KJDEV).
- [ ] Spot-check: `SELECT Full_Contract_Value__c FROM SBQQ__QuoteLine__c LIMIT 1` succeeds as admin.

## 3. Optional safety: pre-stage kill switches OFF

If you want activation decoupled from behavior, flip the Control record's switches off
BEFORE activating flows (Setup → Custom Metadata Types → ALM Code Setting → Control:
`Layer 1 Active` and `Layer 2 Active` unchecked). Flows then activate as no-ops and the
switches become the go-live lever instead of flow activation. **Default plan assumes
switches stay ON** (as deployed) and activation order below is the go-live control.

## 4. Activate `Quote_ALM_Code_Stamp`  *(must precede the master — a Draft subflow faults its caller)*

Setup → Flows → Quote ALM Code Stamp → Activate (or via FlowDefinition metadata).
- [ ] Active. (No behavior change yet — nothing calls it until step 6.)

## 5. Activate `Opp_ALM_Code_AfterSave`  *(Layer 2 goes live here)*

- [ ] Active. From this moment manual OLI edits / data loads on multi-product opps get
      stamped. Watch Flow_Log (step 7 query) for 15 minutes before proceeding.

## 6. Activate the new `Quote_AfterSave_MasterFlow` version  *(Layer 1 go-live)*

Setup → Flows → Quote_AfterSave_MasterFlow → open the newly deployed version → Activate.
- [ ] New version active; prior version listed (that's the instant-rollback target).

## 7. Post-activation smoke + monitoring

```bash
# Fault watch — expect zero rows beyond intentional no-anchor visibility entries
sf data query -o LBR_PROD -q "SELECT CreatedDate, Class_Name__c, Record_Name__c, Error_Description__c FROM Flow_Log__c WHERE Class_Name__c LIKE '%REV-71%' AND CreatedDate = TODAY ORDER BY CreatedDate DESC"

# Behavior check after the first real multi-product QLE save lands (or run a controlled
# test on a designated test opportunity with business approval):
sf data query -o LBR_PROD -q "SELECT Id, Full_Contract_Value__c, Product2.ProductCode FROM OpportunityLineItem WHERE Opportunity.Id = '<test-opp-id>'"
```
- [ ] First coded deal verified end-to-end (quote lines + OLIs match derived family).
- [ ] No unexpected fault rows after 24h. Single-product deals' monetary values untouched
      (spot-check a few recently edited single-product opps).

## 8. Rollback (fast → full)

| Severity | Action | Effect |
|---|---|---|
| Logic misbehaving | CMDT Control → uncheck `Layer 1 Active` / `Layer 2 Active` | Flows run but exit immediately — zero writes, no deploy needed |
| Master hook suspect | Flows → Quote_AfterSave_MasterFlow → activate the PRIOR version | Layer 1 fully detached; rest of master logic restored to pre-REV-71 |
| Layer 2 suspect | Deactivate `Opp_ALM_Code_AfterSave` | Layer 2 off |
| Full retreat | All three above | Field + CMDT + test class remain (inert, additive) — no destructive changes ever needed |

Stamped codes already written remain in the field (they're valid data Integra reads);
remediation of wrongly-stamped lines would be a scripted correction with Integra-owner
sign-off — same protocol as the §7 backfill.

## 9. Deferred / follow-on (separate approvals)

- **§7 backfill audit** (read-only mismatch report on open opps; remediation only with
  explicit approval + Integra confirmation).
- **No-anchor log-noise refinement** — engine logs one visibility row per evaluation
  (2–3 per no-anchor save); add "log only on first detection" before volume becomes annoying.
- **Renewal/amendment live demo** on a contracted account (KJDEV verified the mechanism,
  not CPQ's contract-driven generation).
- **§9 hardening**: field read-only for sales profiles or VR once stable; retire vestigial
  `ALM_Total_Contract_Value__c` (Text); rename `PFC_Log_Fault` to a neutral shared name.
- **Monitoring report** on Flow_Log (REV-71 filter) + consider a scheduled digest.
