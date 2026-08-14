# Phase B — Behaviour Contract (the cockpit)

**Companion to:** `ClaudeCode_Brief_Lead_Conversion.md`, `ClaudeCode_PhaseA_Lead_Conversion_Findings.md`
**Grounding pass:** read-only field/record-type/package describe on **LBR_PROD**, 2026-06-08. Build/deploy target = **KJDEV**.
**Nature of this doc:** a *contract* — the observable behaviour the match-and-select service must guarantee, expressed against verified org fields. No code yet; Phase C turns this into architecture.

---

## 0. What Phase A changed about the contract

| Brief assumed | Reality (Phase A) | Effect on contract |
|---|---|---|
| Office-under-Firm is a target model to build | **Already built**: Account record types `Firm` / `Office`; `Ultimate_Account__c` ("Firm Account") links Office→Firm | Service *resolves into existing structure*, never invents a hierarchy |
| Opp ranking needs an aggregate query | **Already rolled up** on each Office: `No_of_Won_Office_Opportunities__c`, `Val_of_Won_Office_Opportunities__c`, `CFY_*` (current FY = recency), `No_of_Active_Office_Contacts__c` | Ranking reads fields, **no aggregate SOQL in the sync path** |
| `Match_Domain__c` to be created | Not present, but `Approved_Email_Domain__c`, `DaScoopComposer__Domain_1/2__c`, `Website` exist | Decide: reuse `Approved_Email_Domain__c` vs add a clean indexed `Match_Domain__c` (see §10) |
| Extend a custom `*Trigger` handler | No custom trigger framework; engine = managed packages | Extension surface = **flows + one optional handler**; never a new `*Trigger` |
| `Move_Lead_to_Contact…` is the convert | It's a **relink**; the only convert is **native `Lead.convert()`** | Contract targets native convert at both doors |
| LeanData-style matcher may exist | **None** (`LF` = Lead Forensics, visitor ID) | Matcher is **greenfield** |

Two managed packages constrain every write the contract makes:
- **AddressTools (`pw_cc`)** validates/standardises addresses on save (`Validate*BeforeSave`, `pw_cc__CountryLookup__c` on Lead). State & Country picklists are ON (`BillingCountryCode`/`BillingStateCode`). **Any address the service stamps or reparents must be AddressTools-valid (ISO country/state) or the save is rejected.**
- **DupeBlocker (`CRMfusionDBR101`)** can reject an Account/Contact insert as a duplicate mid-convert. Match-first *reduces* this; the failure path must be handled, not assumed away.

---

## 1. Invariants (must always hold)

1. **Match-first, create-last.** Creation of a new Account/Contact requires an explicit "none of these" + a reason. Default action is *convert into an existing record*.
2. **Resolve to an Office, never a Firm.** A Lead converts into an `Office`-record-type Account. The `Firm` (`Ultimate_Account__c` target) is a rollup, never a convert target. No Office under the matched Firm ⇒ offer "create new Office **under this Firm**" — never a new orphan Firm.
3. **Location is the primary Office signal; opportunities only break ties.** The chosen Office's address is stamped onto the Contact (Phase A §1), so a wrong Office propagates a wrong address. Location (country → region → city) selects the Office; opp rollups rank only among location-equivalent Offices.
4. **Convert-into-existing is fill-blanks / engagement-only.** Never clobber verified Contact/Account fields. (Mirrors the existing address-stamp's `IF(ISBLANK(...))` discipline.)
5. **One conversion mechanism.** Both doors resolve to native `Lead.convert()`; the service only *feeds* it the resolved Account/Contact and *records* the outcome.
6. **Every stamped/reparented address is AddressTools-valid** before the owning DML. **No new `*Trigger`.**

---

## 2. Service contract — inputs & outputs

**One `@InvocableMethod` (`MatchAndSelect`), called by both doors.** Pure resolution + ranking; no DML of its own (callers decide to convert/stamp).

**Input** (per record):
- `leadId` *or* `formCompletionId`
- `email` (→ domain), `company`, `countryCode`/`country`, optional `website`
- enrichment keys when present: `DOZISF__ZoomInfo_Company_ID__c`, `LID__LinkedIn_Company_Id__c`

**Output**:
- `resolvedFirmId` (Account, record type Firm) — or null
- `candidateOffices[]`: each `{ officeId, name, billingCountry/State/City, oppOpenCount, oppWonCount (No_of_Won_Office_Opportunities__c), oppWonValue (Val_of_Won_Office_Opportunities__c), cfyWonCount/value (CFY_*), activeContacts (No_of_Active_Office_Contacts__c), locationScore, evidence[], confidence }`, ranked
- `recommendedOfficeId` (top candidate **by location**, opp-tiebroken)
- `contactMatch`: `{ contactId, sameOffice|sameFirm|differentFirm|multiple, action }` (see §6)
- `existingCustomer` flag + `suggestedReasonDisqualified` (picklist value on `Pardot_Form_Completion__c.Reason_Disqualified__c`)
- `confidenceTier`: `ONECLICK | REVIEW | GUIDED_CREATE`
- `conflict` flag (location ≠ opportunities — see §4)

No fuzzy compute in this synchronous path. Fuzzy/dedup stays in the batch pipeline (Phase C / runbook).

---

## 3. Company → Firm resolution (account level)

1. **Domain key.** Derive domain from `email` (strip free-mail). Equality-match against the firm domain key (`Approved_Email_Domain__c` and/or new `Match_Domain__c`, plus `DaScoopComposer__Domain_1/2__c`). Indexed equality only.
2. **Fallback key.** No usable domain ⇒ `company` + `countryCode` exact/normalised match.
3. **Outcome:**
   - **Unique Firm** → proceed to Office selection (§4), tier `ONECLICK`.
   - **2+ Firms** → tier `REVIEW`: company picker, no auto-convert.
   - **No Firm** → tier `GUIDED_CREATE`: after an email + name dedup check (§6), offer "create new Firm + first Office," reason required.
4. Respect `DaScoopComposer__Dont_Match_Leads_to_this_Account__c` — never resolve to an Account flagged do-not-match.

---

## 4. Office selection (within the resolved Firm)

**Primary: location.** Score each Office under the Firm by closeness of `BillingCountryCode` → region → `BillingCity` to the lead's `countryCode`/region/city.
**Tiebreaker among location-equivalent Offices (and the duplicate-survivor rule):** rank by
1. open + total opp count, then
2. `Val_of_Won_Office_Opportunities__c` (won value), then
3. `CFY_*` (current-FY activity = recency), then
4. `No_of_Active_Office_Contacts__c`.

**Conflict rule:** if the location-best Office ≠ the opportunity-best Office, **do not auto-convert** — set `recommendedOfficeId` = location-best, raise `conflict` for dup review (usually a duplicate pair or a small local office). The "most-opps = primary" order is also the merge-survivor rule, so convert-target and merge-survivor stay consistent.
**No Office under the Firm** ⇒ offer "create new Office under this Firm" (never an orphan Firm).

> Owner/territory is intentionally **not** a ranking input (87% of accounts sit with 2 system users). Build `locationScore`/tiebreaker as a pluggable ranker so an owner signal can be added later without rework.

---

## 5. Confidence-adaptive UX (the three doors of the cockpit)

| Tier | Trigger | Native-convert door (Screen Flow) | Pardot door (form-completion) |
|---|---|---|---|
| `ONECLICK` | unique domain → unique Firm, single location-clear Office | one-click confirm of `recommendedOfficeId` | stamp resolved Office onto `Account_Lead__c`/`Account_Contact__c` at form-completion time |
| `REVIEW` | domain → 2+ Firms, or location/opp `conflict` | company/office picker with evidence + opp counts | flag for SDR review; do not auto-stamp the ambiguous one |
| `GUIDED_CREATE` | no key match | guided create after email/name dedup; reason required; sets `new_account_created` | same, reason required |

---

## 6. Contact resolution (people, not just companies)

**Email is the contact match key** (≈6% of contacts already share an email → contact dedup runs in parallel with account dedup, same survivor logic, one level down). On convert, dedup the person across the matched Firm's Offices:

| Situation | Action |
|---|---|
| Same Office, same person (email) | **link**, fill blanks only, log activity/campaign, re-validate if stale — **never** create a second Contact |
| Different Office, same Firm | link + flag *possible move* — **no auto-reparent** (reparent re-fires the address-stamp, Phase A §1) |
| Different Firm (job change) | new Contact at the new Firm + mark the old one "not at company" (`LID__No_longer_at_Company__c` / `Not_at_Company_*`) |
| Multiple email matches | link the primary (most engaged/recent) + flag the duplicate set to merge |

Convert-into-existing is **fill-blanks / engagement-only**; verified fields are never overwritten.

---

## 7. Existing-customer auto-flag

If the resolved Office/Firm has opps or contracts (read `No_of_Won_Office_Opportunities__c` > 0, open opps, or active contracts), surface **"Existing customer / Existing Opportunity"** and pre-fill `Pardot_Form_Completion__c.Reason_Disqualified__c` accordingly. This is a surfaced signal, not an automatic disqualification.

---

## 8. Stamp & close-the-loop (fields the caller writes)

On a resolved convert:
- **Lead:** `Account__c` = resolved Office, `Ultimate_Account__c` = resolved Firm (pre-convert, so native convert lands in the right Account).
- **Form completion:** `Account_Lead__c` / `Account_Contact__c` = resolved Office; existing post-convert flows then back-link `Contact__c` (Phase A §2 chain stays intact).
- **Telemetry:** match-confidence tier, conversion source (native vs Pardot), and a **`new_account_created`** flag → powers the duplicate-creation-rate KPI. (New fields — see §10.)

As duplicates merge down (survivor = most-opps Office), the candidate list collapses toward one and the selector becomes a near-no-op. Convert-target and merge-survivor use the same ranking, by design.

---

## 9. Guardrails inherited from Phase A (the service must not break these)

1. **Address-stamp fence.** Setting `Lead.Account__c` (or reparenting a Contact) changes the Account whose `Billing*` the after-save `Contact_Object_Create_Edit` copies into `Mailing*`. Resolve the Office *before* convert; never auto-reparent an existing Contact across Offices (flag instead).
2. **AddressTools validity.** The resolved Office's `Billing*` must be AddressTools-valid (ISO `BillingCountryCode`/`BillingStateCode`) or the Contact insert during convert is rejected. Prefer Offices with clean addresses; surface "address needs fixing" rather than converting into a bad-address Office.
3. **DupeBlocker.** Convert-into-existing avoids most dup-block rejections; the create path must catch a DupeBlocker rejection and route to REVIEW, not fail silently.
4. **Kill switches.** Existing flows honour `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` / `Disable_Process_Builders__c`. New automation should honour the same switch so the whole stack can be disabled together.
5. **No new `*Trigger`.** Logic lives in the invocable service + flows; at most one new handler, never a competing trigger.

---

## 10. Decisions needed before Phase C (sign-off)

1. **Domain key field.** Reuse `Approved_Email_Domain__c` as the indexed match key, or add a dedicated `Match_Domain__c` (cleaner, enrichable via Clay, avoids overloading an existing field)? *Recommendation: add `Match_Domain__c`, backfill from `Approved_Email_Domain__c` + `Website` + Groove domains.*
2. **Does Groove already match leads→accounts? — RESOLVED (2026-06-08): No.** Of **838,968 unconverted leads, 0 have `Account__c` populated** (1 has `Ultimate_Account__c`). The only leads with `Account__c` set are converted, populated *manually* by users — no automation writes it. Groove's `Dont_Match_Leads_to_this_Account__c` governs *activity* matching, not lead routing. **The service owns `Lead.Account__c` outright (greenfield).** This is also why `UltimateAccountBeforeSavingLead` was obsolete — it copied from an always-empty `Account__c`.
3. **Telemetry fields.** Confirm/create: match-confidence, conversion-source, `new_account_created` (on Lead and/or Pardot_Form_Completion__c).
4. **Region model.** Is there a region field (e.g. `Prospect_s_Region__c` on the form) to use as the middle tier of location scoring, or derive region from country?
5. **"Existing customer" source.** Opp rollups only, or also active Contracts? Confirm the contract object/rollup to read.

---

### Status
Phase A + this contract are read-only/analysis. Nothing built. On sign-off of §10, Phase C specifies the `@InvocableMethod`, the two door integrations, the address-stamp fence, and the test plan (≥75% coverage, 200-record bulk convert, AddressTools/DupeBlocker-rejection handling).
