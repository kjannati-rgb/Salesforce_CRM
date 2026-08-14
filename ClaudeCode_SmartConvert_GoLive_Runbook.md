# Smart Convert — Production Go-Live Runbook

**Target org:** `LBR_PROD` (Law Business Research)
**Package manifest:** `manifest/smartconvert-package.xml` (71 components)
**Validated:** check-only validation against LBR_PROD **passed** — 77/77 components, 28/28 tests, 0 errors (deploy id `0AfPx000001FiszKAC`, quick-deployable for ~10 days).
**Golden rule:** the cockpit is only as good as the match key. **Run the backfill (Stage 2) BEFORE enabling the cockpit (Stage 4)** or reps will match nothing and just create duplicates — the opposite of the goal.

> All commands assume the SF CLI is authed to `LBR_PROD` and proxy env vars are cleared for the session
> (`HTTP(S)_PROXY` — known to hang `sf` otherwise).

---

## Stage 0 — Pre-flight (done / confirm)
- [x] Check-only validation passed against prod (see above).
- [ ] Confirm a maintenance/low-traffic window for Stage 2 (the backfill updates ~740k accounts and fires the full Account trigger stack — DupeBlocker, AddressTools, ZoomInfo, ParentFixer).
- [ ] Confirm who assigns the permission set and edits the Lead page layout (Stage 4).
- [ ] Decide first-run scope for the backfill (recommend a bounded slice first — see Stage 2).

---

## Stage 1 — Deploy the data foundation (fields + CMDTs + backfill Apex)
Deploy **only** the data-layer metadata first; do NOT enable the UI yet. Use the validated job for speed, or deploy the subset.

**Option A — quick-deploy the validated package (fastest, within ~10 days of validation):**
```
sf project deploy quick --job-id 0AfPx000001FiszKAC --target-org LBR_PROD
```
*(This deploys the WHOLE package incl. the LWC/quick action. If you want a strict staged rollout, use Option B to deploy only the data layer first.)*

**Option B — staged: data layer only**
```
sf project deploy start --target-org LBR_PROD --test-level RunSpecifiedTests \
  --tests LeadMatchSelectService_Test --tests MatchDomainBackfill_Test --tests BrandCustomerStatus_Test \
  --metadata \
    "CustomField:Account.Match_Domain__c" "CustomField:Account.Match_Name__c" \
    "CustomObject:Brand_Mapping__mdt" "CustomObject:Free_Mail_Domain__mdt" "CustomMetadata" \
    "ApexClass:LeadMatchSelectService" "ApexClass:LeadMatchSelectService_Test" \
    "ApexClass:BrandCustomerStatus" "ApexClass:BrandCustomerStatus_Test" \
    "ApexClass:MatchDomainBackfill" "ApexClass:MatchDomainBackfill_Test"
```
- [ ] Grant FLS on `Account.Match_Domain__c` / `Match_Name__c` (the `LeadMatchSelect` permission set covers this once deployed — or add to the integration/admin profile that runs the backfill).
- [ ] Sanity check: `SELECT COUNT() FROM Account WHERE Match_Domain__c != null` → expect ~0 (field just created).

---

## Stage 2 — Backfill the match keys (THE critical step)
Populates `Match_Domain__c` (Groove → Website → modal contact-email domain → Approved domain) and `Match_Name__c` (normalised name) across Firms + Offices.

**Operational cautions (read first):**
- Updating accounts fires the **full Account automation stack** (DupeBlocker / AddressTools / ZoomInfo / ParentFixer). On ~740k accounts that is significant load — run **off-peak**.
- The batch is **idempotent** (only touches `Match_Domain__c = null OR Match_Name__c = null`) and uses **best-effort updates** (`Database.update(..., false)`) so row failures don't abort it. Safe to re-run.
- Consider enabling the org automation kill-switches during the run if load is a concern: `Application_Settings__c.Disable_Process_Builders__c` / `Disable_Autolaunch_Lightning_Flow__c` (these gate the custom flows, NOT the managed packages).

**2a — Controlled first run (recommended): a bounded slice.**
Run anonymous Apex that scopes to a sample to confirm behaviour + measure lift before the full sweep:
```apex
// sample 5,000 Firms/Offices with no key yet
List<Account> sample = [SELECT Id, Name, Match_Domain__c, Match_Name__c, Website, Approved_Email_Domain__c,
        DaScoopComposer__Domain_1__c, DaScoopComposer__Domain_2__c
    FROM Account WHERE Match_Domain__c = null AND RecordType.DeveloperName IN ('Firm','Office') LIMIT 5000];
MatchDomainBackfill b = new MatchDomainBackfill();
b.execute(null, sample);   // direct execute on the slice (no batch chaining)
```
- [ ] Measure coverage on the slice (Stage 3 queries). If sane, proceed to full run.

**2b — Full backfill (batch):**
```apex
Database.executeBatch(new MatchDomainBackfill(), 200);   // batch size 200 keeps per-batch SOQL/DML safe
```
- [ ] Monitor: `SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors FROM AsyncApexJob WHERE ApexClass.Name = 'MatchDomainBackfill' ORDER BY CreatedDate DESC LIMIT 1`
- [ ] Re-run if interrupted (idempotent).

---

## Stage 3 — Measure the real match rate (the go/no-go number)
This is the number that decides whether the cockpit is worth enabling.

```sql
-- key coverage after backfill
SELECT COUNT() FROM Account WHERE RecordType.DeveloperName IN ('Firm','Office') AND Match_Domain__c != null
-- vs total
SELECT COUNT() FROM Account WHERE RecordType.DeveloperName IN ('Firm','Office')
-- name-key coverage
SELECT COUNT() FROM Account WHERE Match_Name__c != null
```

**Shadow match-rate on real leads** (what % of open leads would now resolve a firm). Run anonymous Apex over a lead sample and tally tiers:
```apex
Integer oneclick=0, review=0, guided=0;
for (Lead l : [SELECT Id, Email, Company, CountryCode, City, Website FROM Lead
               WHERE IsConverted = false AND Email != null LIMIT 2000]) {
    LeadMatchSelectService.Request r = new LeadMatchSelectService.Request();
    r.email=l.Email; r.company=l.Company; r.countryCode=l.CountryCode; r.region=l.City; r.website=l.Website;
    String tier = LeadMatchSelectService.matchAndSelect(new List<LeadMatchSelectService.Request>{r})[0].confidenceTier;
    if (tier=='ONECLICK') oneclick++; else if (tier=='REVIEW') review++; else guided++;
}
System.debug('ONECLICK '+oneclick+' / REVIEW '+review+' / GUIDED_CREATE '+guided);
```
- [ ] **Decision gate:** if ONECLICK+REVIEW is a healthy majority, proceed. If most are GUIDED_CREATE, the keys still need enrichment (Clay/ZoomInfo) before the cockpit adds value.

---

## Stage 4 — Firm dedup (so a domain resolves to ONE firm)
Use the **installed** tooling (DupeBlocker `CRMfusionDBR101` / DemandTools) — do not hand-roll a destructive merge.
- [ ] Configure a matching scenario on Account keyed on **`Match_Domain__c`** (exact) + **`Match_Name__c`** (your name+website method).
- [ ] **Survivor rule = the firm with the most opportunities** (`No_of_Won_Office_Opportunities__c`, then value) — the SAME ranking the matcher uses, so convert-target and merge-survivor stay consistent.
- [ ] Find clusters to review:
```sql
SELECT Match_Domain__c, COUNT(Id) FROM Account
WHERE RecordType.DeveloperName='Firm' AND Match_Domain__c != null
GROUP BY Match_Domain__c HAVING COUNT(Id) > 1 ORDER BY COUNT(Id) DESC
```

---

## Stage 5 — Enable the cockpit (UI)
Only after Stages 2–4 show a healthy match rate.

**5a — Deploy the UI layer** (skip if you used the full quick-deploy in Stage 1):
```
sf project deploy start --target-org LBR_PROD --test-level RunSpecifiedTests \
  --tests SmartConvertController_Test --tests LeadConvertInvocable_Test \
  --manifest manifest/smartconvert-package.xml
```
**5b — Assign access:**
```
sf org assign permset --name LeadMatchSelect --target-org LBR_PROD --on-behalf-of <user/queue or use Setup>
```
(or assign `LeadMatchSelect` to the SDR profile/permission-set group in Setup.)

**5c — Add the button (manual, ~1 min):** Setup → Object Manager → **Lead** → Page Layouts → your SDR layout → **Mobile & Lightning Experience Actions** → drag **Smart Convert** into the bar → Save. (Repeat per layout/record type you want it on.)

**5d — Smoke test** on 2–3 real leads (a clean match, an existing customer, a no-match) before announcing.

> Note: the `Lead_Smart_Convert` flexipage in the package is a demo record page (highlights + detail, no embedded component) — you do **not** need to activate it; the quick-action button is the launcher.

---

## Stage 6 — Pardot door (Door 2) — separate, later
`Pardot_Smart_Resolve` deploys as **Draft** (LBR_PROD deploys flows inactive). It is **runtime-unverified** — there is no Pardot integration in the sandbox.
- [ ] Validate in a **Pardot-connected** environment: create a real `Pardot_Form_Completion__c` and confirm `Account_Lead__c` gets stamped.
- [ ] Known limitation: `Country__c` is a country **name**, not ISO — office *location* ranking is weak via Pardot (firm still resolves by domain). Add a country-name→ISO map if needed.
- [ ] Activate only after validation (via FlowDefinition / Setup).

---

## Rollback & safety
- **Stages 1–2 are additive** (new fields + data) — nothing existing changes; no rollback needed. The backfill only *fills blanks*.
- **Cockpit (Stage 5)** is a new button + component — to disable, remove the quick action from the layout (instant) or unassign the permission set. The component does **no DML itself**; all writes go through the standard convert.
- **Convert behaviour** mirrors native convert (it *is* native convert under the hood) + records telemetry. Managed-package rejections (AddressTools/DupeBlocker) are surfaced to the rep, not swallowed.

---

## Post-go-live monitoring (the telemetry is now real)
Build a simple report/dashboard on these `Lead` fields (all stamped at convert):

| Metric | Field(s) |
|---|---|
| Duplicate-creation rate | `New_Account_Created__c` (% true) by week |
| Match quality mix | `Match_Confidence__c` (ONECLICK / REVIEW / GUIDED_CREATE) |
| **Where the matcher is wrong** | `Overrode_Recommendation__c` (true) → review those firms/offices |
| **Where enrichment is needed** | `Manual_Search_Used__c` (true) → prioritise those domains |
| New-account reasons | `Create_Reason__c` |
| SCV-preserving disqualifies | `Disqualified_At_Convert__c` + `Disqualify_Reason__c` |
| Source | `Conversion_Source__c = 'Smart Convert'` |

`Overrode_Recommendation__c` and `Manual_Search_Used__c` are the **feedback loop** — they tell the data team exactly where to focus enrichment/dedup next. Review weekly.

---

## One-line summary of the order that matters
**Deploy data → run backfill → measure match rate → dedup firms → enable cockpit → (later) validate Pardot.**
Skipping the backfill is the only way to make this *worse* than today.
