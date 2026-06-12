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
sf project deploy start \
  -m "CustomField:SBQQ__QuoteLine__c.Full_Contract_Value__c" \
  -m "CustomObject:ALM_Code_Setting__mdt" \
  -m "CustomMetadata:ALM_Code_Setting.Control" \
  -m "CustomMetadata:ALM_Code_Setting.Family_Law_com_Premium" \
  -m "CustomMetadata:ALM_Code_Setting.Family_GLL" \
  -m "CustomMetadata:ALM_Code_Setting.Family_Law_com_International" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Law_com_Pro" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Mid_Market_Pro" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_GLBM" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Law_com_Intl_Bundle" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Law_com_Radar" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Law_com_VerdictSearch" \
  -m "CustomMetadata:ALM_Code_Setting.Parent_Law_com_Premium" \
  -m "Flow:Quote_ALM_Code_Stamp" -m "Flow:Opp_ALM_Code_AfterSave" \
  -m "Flow:Quote_AfterSave_MasterFlow" \
  -m "ApexClass:REV71_ALMCodeFlow_Test" \
  -o LBR_PROD --test-level RunSpecifiedTests --tests REV71_ALMCodeFlow_Test --dry-run   # validate first
# then re-run WITHOUT --dry-run
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
