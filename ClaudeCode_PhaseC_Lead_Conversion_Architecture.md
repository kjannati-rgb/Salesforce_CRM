# Phase C — Architecture Spec

**Companion to:** `ClaudeCode_Brief_Lead_Conversion.md`, `ClaudeCode_PhaseA_Lead_Conversion_Findings.md`, `ClaudeCode_PhaseB_Lead_Conversion_Contract.md`
**Grounded on:** read-only discovery of LBR_PROD (2026-06-07/08). **Build/deploy target = KJDEV only.** Nothing to production without explicit sign-off.
**Defaults applied** (Phase B §10): add `Match_Domain__c`; create 3 telemetry fields; region tier = `Prospect_s_Region__c`; existing-customer = opp rollups (Contracts TBD). Decision 2 (Groove) is closed — service owns `Lead.Account__c`.

---

## 1. Component inventory (what gets built in KJDEV)

| # | Component | Type | Role |
|---|---|---|---|
| C1 | `LeadMatchSelectService` | Apex class, `@InvocableMethod` | The single match-and-select engine. No DML. Called by both doors. |
| C2 | `LeadMatchSelectService_Test` | Apex test | ≥75% coverage; bulk + rejection cases. |
| C3 | `Match_Domain__c` | Account field (Text, External Id, indexed) | Indexed equality key for firm resolution. Backfilled. |
| C4 | Telemetry fields | Lead + `Pardot_Form_Completion__c` fields | `Match_Confidence__c` (picklist), `Conversion_Source__c` (picklist), `New_Account_Created__c` (checkbox). |
| C5 | `Convert_Lead_Guided` | Screen Flow (Lead) | Door 1 UX: calls C1, shows ranked Offices, converts via core **Convert Lead** action. |
| C6 | `MatchSelect_Office_Picker` (optional) | LWC | Only if the Flow screen can't render the ranked-evidence picker richly enough. |
| C7 | Refactor `On_Pardot_Form_Creation` + add stamp | Flow (Pardot form) | Door 2: call C1 at form-completion, stamp `Account_Lead__c`/`Account_Contact__c`. |
| C8 | `LeadMatch_DedupBatch` (later) | Batch/Queueable | Fuzzy + contact/account dedup out of the sync path. Not in MVP. |
| C9 | `Match_Domain_Backfill` | Anonymous Apex / batch | One-off: populate `Match_Domain__c` from `Approved_Email_Domain__c` + `Website` + Groove domains. |

**Not built:** any new `*Trigger`; any change to managed packages (AddressTools, DupeBlocker, ZoomInfo, Groove, Lead Forensics) — config only.

---

## 2. C1 — `LeadMatchSelectService` (the engine)

**Shape.** `global with sharing class LeadMatchSelectService` exposing:
```
@InvocableMethod(label='Match and Select Account')
public static List<Result> matchAndSelect(List<Request> requests)
```
- `with sharing` — respects the running SDR's visibility.
- Bulk-safe: one `Request` per lead/form; method handles up to 200 in a single transaction (200-record bulk-convert test depends on it).
- **No DML** — pure resolution. Callers (C5/C7) own all writes, so the engine never trips DupeBlocker/AddressTools itself.

**Request** (from Phase B §2): `recordId`, `email`, `company`, `countryCode`, `region`, `website`, `zoomInfoId`, `linkedInCompanyId`.
**Result** (from Phase B §2): `resolvedFirmId`, `candidateOffices[]`, `recommendedOfficeId`, `contactMatch`, `existingCustomer`, `suggestedReasonDisqualified`, `confidenceTier`, `conflict`.

**Query strategy (governor-safe, ≤4 SOQL regardless of batch size):**
1. Build domain set from all requests' emails (+ website host). One query:
   `SELECT Id, Ultimate_Account__c, RecordType.DeveloperName, Match_Domain__c, Approved_Email_Domain__c, DaScoopComposer__Domain_1__c, DaScoopComposer__Domain_2__c FROM Account WHERE Match_Domain__c IN :domains OR Approved_Email_Domain__c IN :domains` — bulk, indexed.
2. Resolve Firm per request (group matched Accounts by `Ultimate_Account__c`; if Account is itself a Firm, use its Id).
3. One query for Offices under the resolved Firms, selecting the **pre-rolled-up ranking fields** (no aggregate):
   `SELECT Id, Name, BillingCountryCode, BillingStateCode, BillingCity, Ultimate_Account__c, No_of_Won_Office_Opportunities__c, Val_of_Won_Office_Opportunities__c, CFY_No_of_Won_Office_Opportunities__c, CFY_Val_of_Won_Office_Opportunities__c, No_of_Active_Office_Contacts__c, DaScoopComposer__Dont_Match_Leads_to_this_Account__c FROM Account WHERE RecordType.DeveloperName='Office' AND Ultimate_Account__c IN :firmIds`
4. One query for contact email matches: `SELECT Id, AccountId, Account.Ultimate_Account__c, Email, ... FROM Contact WHERE Email IN :emails`.

   *(Optional 5th: open-opp existence per Office if the rollup doesn't expose "open" count — confirm in §7.)*

**Ranking (in Apex, no SOQL):** location score first (countryCode → region → city), then opp-rollup tiebreaker order from Phase B §4. Implement the ranker as a strategy object so an owner/territory signal can be added later (Phase B note).

**Confidence tiering:** unique-domain→unique-Firm + single location-clear Office ⇒ `ONECLICK`; domain→2+ Firms or location/opp `conflict` ⇒ `REVIEW`; no key ⇒ `GUIDED_CREATE`.

**No fuzzy in the sync path** — only exact/normalised equality. Fuzzy lives in C8.

---

## 3. Door 1 — native convert → `Convert_Lead_Guided` Screen Flow (C5)

**Mechanism:** Salesforce Flow's standard **"Convert Lead" core action** (available API ≥56; org is API 66) converts a Lead into a **specified existing `AccountId` and `ContactId`** without Apex. So the whole door is declarative: Screen Flow → C1 → picker screen → Convert Lead action.

**Flow steps:**
1. Get Lead fields → call **C1** (`recordId`=Lead.Id, email/company/country/region).
2. **Branch on `confidenceTier`:**
   - `ONECLICK`: confirmation screen showing `recommendedOfficeId` (name, city, opp evidence) → Convert.
   - `REVIEW`: picker screen of `candidateOffices[]` (C6 LWC if richer than a Flow datatable is needed) → Convert into chosen Office.
   - `GUIDED_CREATE`: email/name dedup result → "create new Office under Firm" (or new Firm+Office), **reason required** → Convert with new AccountId; set `New_Account_Created__c=true`.
3. **Pre-convert stamp:** set `Lead.Account__c` = chosen Office, `Lead.Ultimate_Account__c` = Firm (so downstream automation and reporting see the resolved target).
4. **Convert Lead action** with `AccountId` = chosen Office, `ContactId` = matched Contact when `contactMatch` says same-office (fill-blanks), else new Contact.
5. Write telemetry (C4): `Match_Confidence__c`, `Conversion_Source__c='Native'`.

**Surface:** replace/augment the standard Convert button with a Lightning action that launches `Convert_Lead_Guided` (the standard convert is left intact as a fallback; no custom convert exists today so nothing is overwritten).

**Why not pure native modal:** the Lightning convert modal matches accounts by Company *name* only, can't rank by location/opps, can't show evidence, and can't enforce Office-not-Firm. The Screen Flow gives us that control while still using the platform convert under the hood.

---

## 4. Door 2 — Pardot form completion → stamp (C7)

The Pardot post-convert chain (Phase A §2) stays intact. We add resolution **at form-completion time** so the resolved Office is known before/independent of the manual convert:

1. On `Pardot_Form_Completion__c` create/update (where `Lead__c` set, `Account_Lead__c` empty): call **C1** (`recordId`=form.Id, email/company/country from form fields `Email__c`/`Company__c`/`Country__c`/`Prospect_s_Region__c`).
2. Stamp `Account_Lead__c` (and `Account_Contact__c` when a contact match exists) = `recommendedOfficeId` when tier `ONECLICK`; otherwise leave blank and set `Match_Confidence__c='Review'` for SDR follow-up.
3. Set `Conversion_Source__c='Pardot'`, existing-customer flag, and pre-fill `Reason_Disqualified__c` when `existingCustomer`.
4. **Do not** convert here — the SDR still drives convert via Door 1; this door pre-resolves so Door 1 opens at `ONECLICK`. Existing flows `Move_Lead_to_Contact_on_Pardot_Form` / `On_Pardot_Form_Creation` continue to back-link post-convert unchanged.

Implementation: extend `On_Pardot_Form_Creation` (already after-save on this object) to invoke C1, rather than adding a competing flow. Honour the existing kill switch.

---

## 5. Address-stamp fence (the must-not-break)

From Phase A §1: after-save `Contact_Object_Create_Edit` copies `Account.Billing*` → `Contact.Mailing*` (fill-blanks) on the Contact created by convert, and AddressTools then validates it.

**Fence rules in the build:**
- The service resolves the Office **before** convert; convert lands the Contact in the right Office first time, so the stamp fires once with the correct address. No post-hoc reparent.
- **Never auto-reparent an existing Contact across Offices** (Phase B §6 "different office, same firm" → flag only). Reparenting re-fires the stamp and can overwrite a verified address.
- **AddressTools pre-check:** before offering an Office as `ONECLICK`, verify it has a valid `BillingCountryCode` (and `BillingStateCode` where the country requires it). An Office with an invalid/blank country is demoted to `REVIEW` with an "address needs fixing" note — converting into it risks an AddressTools rejection on the Contact insert.

---

## 6. Data-model changes (C3/C4) — declarative, additive only

- **`Account.Match_Domain__c`** — Text(255), External Id, Unique=false, indexed. Backfilled by C9 from `Approved_Email_Domain__c` → else host of `Website` → else Groove `Domain_1/2`. (Adding rather than overloading keeps the existing field's meaning intact; Clay enrichment writes here.)
- **`Match_Confidence__c`** (picklist: `OneClick`/`Review`/`GuidedCreate`) on Lead + form.
- **`Conversion_Source__c`** (picklist: `Native`/`Pardot`) on Lead + form.
- **`New_Account_Created__c`** (checkbox) on Lead + form → duplicate-creation-rate KPI.
- FLS: expose via permission set (follow the existing pattern in `force-app/main/default/permissionsets/`).

---

## 7. Async boundary (C8 — later, not MVP)

Sync path = exact/indexed equality only. The batch pipeline owns: fuzzy company/domain matching, the ≈6% shared-email contact dedup, firm de-duplication, and `Match_Domain__c` enrichment. Survivor rule = most-opps Office (same ranking as the selector), so convert-target and merge-survivor stay consistent and the candidate list collapses over time. Sequenced per `ClaudeCode_Runbook_Account_Identity.md` (match keys first).

**Open:** confirm whether an "open opp count" rollup exists on Office; if not, either add a rollup (Rollup Helper `rh2` is installed) or accept one extra SOQL in C1 for open-opp existence.

---

## 8. Test plan (C2)

1. **Unique domain → ONECLICK** single Office: asserts `recommendedOfficeId`, tier.
2. **Domain → 2 Firms → REVIEW**: no auto-resolve.
3. **Location vs opps conflict**: recommends location-best, raises `conflict`.
4. **No key → GUIDED_CREATE**: dedup runs, reason required, `New_Account_Created__c`.
5. **Contact email dedup**: same-office link/fill-blanks; job-change → new contact + old "not at company"; multiple → primary + flag.
6. **200-record bulk convert**: SOQL/DML within limits; ≤4 queries in C1.
7. **AddressTools rejection handled**: convert into an Office with invalid country → caught, routed to REVIEW, no orphan records.
8. **DupeBlocker rejection handled**: create path hitting a dup → caught → REVIEW.
9. ≥75% coverage on C1 (target ≥90% on ranking/tiering logic).

---

## 9. Deployment sequence (KJDEV → prod, on sign-off)

1. Deploy C3/C4 fields + permission set; run C9 backfill in KJDEV.
2. Deploy C1/C2; run tests.
3. Build/activate C5 + (optional) C6; wire the Lead action.
4. Extend C7; smoke-test the Pardot door.
5. **Prod flow gotcha (known):** LBR_PROD deploys flows as **Draft** — after deploy, activate via FlowDefinition before pointing any page/action at the flow. (See memory: *Prod deploys flows as Draft*.)
6. Bulk-convert regression in a prod-like sandbox before any prod sign-off.

---

## 10. Open items carried into build

- **§10.1** `Match_Domain__c` backfill source precedence — confirm free-mail strip list and Groove-domain trust.
- **§10.3/4/5** telemetry field API names, `Prospect_s_Region__c` value→region mapping, and whether **Contracts** also count toward "existing customer" (only opp rollups assumed for now).
- **§7** open-opp rollup existence on Office.
- **Door-1 picker:** decide Flow datatable vs C6 LWC after building the ONECLICK path (escalate only if needed — brief's guidance).
- **LeanData/ZoomInfo:** none compete for `Lead.Account__c` (confirmed); ZoomInfo enrichment can *feed* `Match_Domain__c` but is not a dependency.

---

### Status
Phases A–C are analysis/spec only. **Nothing built.** On sign-off, MVP = C1+C2+C3+C4+C5+C7+C9 (Door-1 ONECLICK/REVIEW + Door-2 stamp); C6/C8 are fast-follows. First build step would be C3/C4 fields + C1 with its test, in KJDEV.
