# Scope — Match-key backfill in production (the go-live gate)

**What:** populate `Account.Match_Domain__c` (+ `Match_Name__c`) across all Firm/Office accounts in `LBR_PROD` by running `MatchDomainBackfill`, then measure the real match rate. **This is the gating dependency** — the Smart Convert cockpit is only as good as the match key. Enabling the cockpit before this is done makes reps match nothing and create duplicates: strictly worse than today.

**Target org:** `LBR_PROD`. **KJDEV is already done** (fields + Apex live, tested).

---

## Current prod baseline (read-only, pulled 2026-06-17)

| Measure | Count | % of accounts |
|---|---|---|
| Firm + Office accounts (the backfill scope) | **738,958** | 100% |
| — Firms | 332,457 | |
| — Offices | 406,501 | |
| Have Groove `DaScoopComposer__Domain_1__c` | 477,731 | **64.6%** |
| Have `Website` | 365,405 | 49.4% |
| Have `Approved_Email_Domain__c` (today's "match key") | **431** | **0.06%** |

The match key is effectively empty today (431 records). The raw material is rich — Groove alone covers ~65%, and the backfill's cascade adds Website + the modal contact-email domain on top. **Expected `Match_Domain__c` coverage after backfill: ~70–80%+** (floor 64.6% from Groove; the union with Website + the contact-email step lifts it — the pilot measures the real number).

---

## How the backfill works (recap)
`MatchDomainBackfill` (Batchable + Stateful, batch size 200, idempotent — only touches rows where `Match_Domain__c = null OR Match_Name__c = null`, best-effort `Database.update(..., false)` so row failures don't abort). Per account it derives:
- **`Match_Domain__c`** = Groove Domain_1/2 → Website host → modal non-free-mail contact-email domain → Approved_Email_Domain (first hit wins; free-mail filtered via `Free_Mail_Domain__mdt`).
- **`Match_Name__c`** = normalised firm name (lowercase, strip punctuation + legal suffixes, drop leading "the"; conservative — keeps Intl/Group/Holdings).

---

## Phase 0 — prerequisites (before any batch runs)
1. **Deploy the data layer to prod** (additive — new fields + CMDTs + Apex; no UI). Quick-deploy the validated job `0AfPx000001FrbJKAS` (whole package, ~10-day window) **or** deploy the data subset only:
   `CustomField Account.Match_Domain__c, Account.Match_Name__c` · `CustomObject Brand_Mapping__mdt, Free_Mail_Domain__mdt` + their records · `ApexClass LeadMatchSelectService, MatchDomainBackfill, BrandCustomerStatus, SalesMotionService` (+ tests).
2. **Grant FLS** on `Match_Domain__c` / `Match_Name__c` to the integration/admin user that runs the batch (the `LeadMatchSelect` permset covers this).
3. **Confirm the raw-material fields exist in prod** (they do — counts above) and that `Free_Mail_Domain__mdt` deployed.
4. **Pick an off-peak window** and a **named owner** with "Modify All Data" on Account to launch + monitor.
5. **Decide kill-switches** (see Risk #1). `Application_Settings__c.Disable_Process_Builders__c` / `Disable_Autolaunch_Lightning_Flow__c` gate the **custom** flows; they do **not** gate managed packages.

---

## Phase 1 — bounded pilot (5,000 accounts)
Run the slice directly (no batch chaining) so you can watch behaviour before the full sweep:
```apex
List<Account> sample = [SELECT Id, Name, Match_Domain__c, Match_Name__c, Website, Approved_Email_Domain__c,
        DaScoopComposer__Domain_1__c, DaScoopComposer__Domain_2__c
    FROM Account WHERE Match_Domain__c = null AND RecordType.DeveloperName IN ('Firm','Office') LIMIT 5000];
new MatchDomainBackfill().execute(null, sample);
```
**Measure on the slice:**
- Coverage lift: of the 5,000, how many got `Match_Domain__c` / `Match_Name__c` populated? (Expect a strong majority.)
- Error rate: any row failures (check debug / a re-query of nulls).
- **Automation load (the real unknown — Risk #1):** watch ZoomInfo/DupeBlocker job queues + AddressTools credit usage during the slice. Confirm a field-only update (no address/parent change) does **not** trigger heavy managed re-processing.
- **Go/no-go to full run:** coverage sane + no load/credit surprises.

---

## Phase 2 — full backfill
```apex
Database.executeBatch(new MatchDomainBackfill(), 200);
```
- **Volume:** 738,958 accounts ÷ 200 = **~3,695 batches**. Runtime depends entirely on per-record trigger cost — calibrate from the pilot (could be a few hours to overnight). Run **off-peak**; it's safe to let it run long.
- **Monitor:** `SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors FROM AsyncApexJob WHERE ApexClass.Name = 'MatchDomainBackfill' ORDER BY CreatedDate DESC LIMIT 1`
- **Idempotent:** safe to re-run if interrupted — it only fills blanks. Abort anytime via `System.abortJob` on the AsyncApexJob id; already-committed batches persist.

---

## Phase 3 — measure the real match rate (the go/no-go number)
```sql
-- key coverage after backfill
SELECT COUNT() FROM Account WHERE RecordType.DeveloperName IN ('Firm','Office') AND Match_Domain__c != null
SELECT COUNT() FROM Account WHERE Match_Name__c != null
```
**Shadow match-rate on real leads** — the number that decides whether to enable the cockpit. Run `LeadMatchSelectService.matchAndSelect` over a sample of open leads and tally tiers:
```apex
Integer oneclick=0, review=0, guided=0;
for (Lead l : [SELECT Id, Email, Company, CountryCode, City, Website FROM Lead
               WHERE IsConverted = false AND Email != null LIMIT 2000]) {
    LeadMatchSelectService.Request r = new LeadMatchSelectService.Request();
    r.email=l.Email; r.company=l.Company; r.countryCode=l.CountryCode; r.region=l.City; r.website=l.Website;
    String t = LeadMatchSelectService.matchAndSelect(new List<LeadMatchSelectService.Request>{r})[0].confidenceTier;
    if (t=='ONECLICK') oneclick++; else if (t=='REVIEW') review++; else guided++;
}
System.debug('ONECLICK '+oneclick+' / REVIEW '+review+' / GUIDED_CREATE '+guided);
```
**Decision gate:** if `ONECLICK + REVIEW` is a healthy majority → proceed to dedup + cockpit. If most are `GUIDED_CREATE` → keys still need enrichment (Clay/ZoomInfo) before the cockpit adds value.

---

## Phase 4 — handoff (sequenced after a healthy match rate)
1. **Firm dedup** keyed on `Match_Domain__c` (+ `Match_Name__c`) via DupeBlocker/DemandTools, survivor = most-opps firm (the matcher's own ranking). Severe today (Dentons ×15, KPMG ×11).
2. **Enable the cockpit** (permset + quick action) for a pilot SDR group.
3. **Pardot door** later, in a Pardot-connected org.

---

## Risk register
1. **Managed-package load on 738k updates (biggest unknown).** The kill-switches gate custom flows only; DupeBlocker / AddressTools / ZoomInfo / ParentFixer triggers fire on Account update regardless. BUT the backfill only writes two custom text fields (`Match_Domain__c`, `Match_Name__c`) — no address, no name, no parent change — so the heaviest managed logic (AddressTools verification = paid credits; ParentFixer reparenting) likely will **not** fire (they're field-scoped). DupeBlocker/ZoomInfo behaviour on a generic update is the thing to **confirm in the pilot** before the full sweep. Mitigation: off-peak run; pilot-first; abort if credit/job spikes appear.
2. **Runtime / async slots.** ~3,695 batches may run for hours and consume async capacity — run off-peak; it self-throttles via the batch framework.
3. **Partial / interrupted run.** Idempotent + best-effort → re-run safely; row failures are logged, not fatal.
4. **Rollback.** None needed — purely additive (fills two blank fields). To "undo," null the fields; nothing existing is mutated.
5. **Free-mail / personal domains.** ~6% of open leads are free-mail; filtered out of `Match_Domain__c` by design (they route to name/manual/enrichment fallbacks), so they legitimately stay blank.

---

## Decisions for you
- **Quick-deploy the whole validated package, or staged data-layer-only first?** (Recommend data-layer-only for a clean staged rollout; the cockpit comes after the match-rate gate.)
- **Kill-switches during the run — on or off?** (Recommend leaving custom automation ON unless the pilot shows custom-flow load; the managed packages are the real variable.)
- **Who owns the run + the window?** (Needs Modify All Data + an agreed off-peak slot.)

## One-line order that matters
**Deploy data layer → pilot 5k → full backfill → measure match rate (go/no-go) → dedup → enable cockpit.** Skipping the backfill is the only way to make Smart Convert *worse* than today.
