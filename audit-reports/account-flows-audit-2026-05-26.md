# Account Flows — Best-in-Class Audit

**Org:** `lawbusinessresearch--kjdev` (KJDEV sandbox) · **API 66.0**
**Date:** 2026-05-26
**Scope:** Every non-managed Flow that touches the Account object (read-only analysis — no org changes made)
**Reference standard:** Salesforce *Architect's Guide to Record-Triggered Automation* and *Flow Best Practices* (Salesforce Help). Key principles cited inline: before-save for same-record updates; one record-triggered flow per object/context; bulkification & no SOQL/DML in loops; fault paths on every DML/external call; no hardcoded IDs; minimize executions with entry criteria.

---

## Phase 1 — Discovery method & what was found

**How flows were enumerated**
1. Cleared dead corporate proxy env vars (`HTTP_PROXY`/`HTTPS_PROXY` → `194.9.107.67:80`) per saved memory, otherwise all org calls hang.
2. `FlowDefinitionView` (standard SOQL) for all non-managed definitions: **231 flow definitions** — 188 AutoLaunched, 24 Screen (`Flow`), 19 `Workflow` (= **Process Builders**).
3. Tooling API `Flow` object for per-version `Status`/`ApiVersion`/`VersionNumber` (the only reliable source — `FlowVersionView` rejects relationship/ordered queries with `INVALID_OPERATION`).
4. Bulk `sf project retrieve --metadata Flow` (232 files) → grepped `<object>Account</object>` to find indirect Account-touchers and `<flowName>` to map the subflow call graph.
5. Cross-referenced Apex (`ApexTrigger WHERE TableEnumOrId='Account'`).

**Anomalies found along the way (important caveats)**
- **The bulk retrieve returns the *latest* version, not the *active* one.** For 2 of 3 Account-triggered flows the active version ≠ latest, so the on-disk file is an **Obsolete** version. I explicitly re-retrieved the running versions (`Flow:Account_is_Inactive-2`, `Flow:Account_Object_Create_Edit_1-10`) and analysed those. Anyone reading the default `force-app` files is reading the wrong logic.
- `Account_is_Inactive` active version is **v2**, but v3 and v4 exist as Obsolete — someone **rolled back** to an older version.
- `Account_Object_Create_Edit` exists **twice**: as an inactive Process Builder (`ProcessType=Workflow`, API 49) *and* as the migrated record-triggered flow `Account_Object_Create_Edit_1`. The old PB was never deleted.
- `Sample_Flow_to_Debug` is an **active, orphaned** (no callers) debug flow that performs 2 DMLs including an Account write.

**What was filtered out**
- All managed-package flows (`NamespacePrefix != null`).
- 216 flow definitions that never reference the Account object.
- Note on Account screen/scheduled flows: none of the 15 Account-touchers are Screen or true Scheduled flows. **BUSINESS CONTEXT NEEDED:** confirm no Account *page-layout/quick-action* screen flows exist that are launched purely from the UI (these wouldn't show an Account data operation if they only display fields) — layouts/quick actions were not exhaustively parsed.

**The 15 flows that touch Account** (3 triggered *on* Account; 12 triggered on other objects or autolaunched that read/write Account):

| # | Flow | Relationship to Account |
|---|---|---|
| 1 | Account_Object_Create_Edit_1 | Record-triggered **on Account** (after-save) |
| 2 | Account_is_Inactive | Record-triggered **on Account** (after-save) |
| 3 | Account_Update_Industry_Category | Record-triggered **on Account** (before-save) |
| 4 | Account_Object_Create_Edit | **Inactive Process Builder** on Account (legacy) |
| 5 | Update_Tax_Country_Code | Autolaunched **subflow** of #1; reads/writes Account |
| 6 | Lead_AL_UpdateGenericFields | Autolaunched (called by Lead master flow); writes Account |
| 7 | Sample_Flow_to_Debug | Autolaunched, orphaned; writes Account |
| 8 | Update_Account_Organisation_Type_from_Contact_Organisation_Type | Contact after-save; updates Account |
| 9 | Quote_BeforeSave_UpdateQuoteFields | Quote before-save; reads Account |
| 10 | UltimateAccountBeforeSaving | Opportunity before-save; reads Account |
| 11 | Check_Completeness_of_Contact_Roles | Opportunity before-save; reads Account |
| 12 | Entitlement_Flow | Case before-save; reads Account |
| 13 | Task_AL_FirmUpdate | Task after-save; updates Account *(inactive)* |
| 14 | Gong_Conversations_Create_Edit | Contact/Conversation after-save; reads Account *(inactive)* |
| 15 | UltimateAccountBeforeSavingLead | Lead before-save; reads Account *(inactive)* |

---

## Phase 2 — Inventory (sorted by Risk Rating, High first)

Fault-path column note: *before-save* flows that only set fields on the triggering record perform **no DML** and cannot have fault paths — those are marked "n/a (before-save)" rather than flagged.

| Flow Label | API Name | Type | Trigger Obj + Condition | Active Ver (other versions) | API Ver | Active | Last Modified | Elements | Desc | Fault paths on DML | Risk + reason |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Account Object - Create/Edit | `Account_Object_Create_Edit_1` | RecordAfterSave | Account, Create+Update | v10 (11 vers; v8 Draft, v1 InvalidDraft, rest Obsolete) | 60 | Y | 2024+ | ~25 | Y | **MISSING (14 DML)** | **HIGH** — monolithic after-save doing 8 jobs; same-record updates done in after-save (should be before-save); scheduled mass-update of unbounded child records; zero fault handling; hardcoded picklists |
| Update Tax Country Code | `Update_Tax_Country_Code` | Autolaunched (subflow) | called per-Account from #1 | v2 (2 vers) | **49** | Y | — | 6 | Y | **MISSING (2 DML)** | **HIGH** — re-queries the triggering Account (redundant SOQL), then DMLs it in after-save context; no fault paths; API 49 (17 releases old) |
| NOT AT COMPANY: Account is Inactive | `Account_is_Inactive` | RecordAfterSave | Account, Update, `Status__c = Inactive` | v2 (4 vers; v3/v4 Obsolete — rolled back) | **56** | Y | — | 5 | N* | **MISSING (1 DML)** | **HIGH** — no `ISCHANGED` entry criteria → re-runs on *every* edit of an inactive account; no fault path; API 56 |
| Lead AL Update Generic Fields | `Lead_AL_UpdateGenericFields` | Autolaunched | called by `Lead_AfterUpdate_MasterFLow`; writes Account | v4 (3 vers) | 64 | Y | — | ~13 | Y | **MISSING (6 DML)** | **HIGH** — **hardcoded Campaign Id** `701Px00000Vp6HkIAJ`; 6 DML with no fault paths |
| Sample Flow to Debug | `Sample_Flow_to_Debug` | Autolaunched | orphaned (no callers); writes Account | v1 | *(blank)* | Y | — | 5 | N | present (2) | **HIGH** — active debug/test artifact in a near-prod sandbox; 2 DML incl. Account; **BUSINESS CONTEXT NEEDED** before removal |
| Account Object - Create/Edit (PB) | `Account_Object_Create_Edit` | Process Builder (`Workflow`) | Account | inactive (8 vers) | **49** | N | — | ~24 | N | n/a (PB) | **MEDIUM** — dead legacy Process Builder superseded by #1; low runtime risk but high confusion/tech-debt; should be deleted |
| Account Update Industry Category | `Account_Update_Industry_Category` | RecordBeforeSave | Account, Create+Update, Industry/Override/Provider changed | v4 (4 vers; v2 InvalidDraft) | 62 | Y | — | 1 | Y | n/a (before-save) | **MEDIUM** — correct before-save pattern, but ~30-branch hardcoded `CASE`/picklist mapping inline; no kill-switch |
| Update Account Org Type from Contact | `Update_Account_Organisation_Type_from_Contact_Organisation_Type` | RecordAfterSave | Contact, Create+Update | v7 (7 vers) | **52** | Y | — | 3 | Y | **MISSING (1 DML)** | **MEDIUM** — cross-object Account update in after-save with no fault path; API 52 |
| Quote BeforeSave Update Quote Fields | `Quote_BeforeSave_UpdateQuoteFields` | RecordBeforeSave | Quote, Create+Update | v3 (3 vers) | 65 | Y | — | 7 | Y | n/a (before-save) | **MEDIUM** — **hardcoded RecordType Id** `0126g000000Om7TAAS` |
| Check Completeness of Contact Roles | `Check_Completeness_of_Contact_Roles` | RecordBeforeSave | Opportunity, Create+Update | v4 (4 vers) | **49** | Y | — | ~15 | Y | n/a (before-save) | **MEDIUM** — 7 decisions / 3 Gets; API 49; complex but no DML |
| Entitlement Flow | `Entitlement_Flow` | RecordBeforeSave | Case, Create | v1 | **57** | Y | — | 3 | Y | n/a (before-save) | **MEDIUM** — reads Account; API 57; small |
| Ultimate Account Before Saving | `UltimateAccountBeforeSaving` | RecordBeforeSave | Opportunity, Create | v1 | **49** | Y | — | 4 | Y | n/a (before-save) | **LOW** — small, correct pattern; only flag is API 49 |
| Task AL Firm Update | `Task_AL_FirmUpdate` | RecordAfterSave | Task, Create+Update | — (4 vers) | 64 | **N** | — | ~13 | Y | MISSING (3 DML) | **LOW** — inactive; but hardcoded RecordType Id + no fault paths if reactivated |
| Gong Conversations Create/Edit | `Gong_Conversations_Create_Edit` | RecordAfterSave | Contact, Create+Update | — (1 ver) | 61 | **N** | — | 3 | Y | MISSING (1 DML) | **LOW** — inactive; hardcoded RecordType Id `0126g000000OhUTAA0` |
| Ultimate Account Before Saving (Lead) | `UltimateAccountBeforeSavingLead` | RecordBeforeSave | Lead, Create+Update | — (1 ver) | **49** | **N** | — | 4 | Y | n/a (before-save) | **LOW** — inactive; API 49 |

\* `Account_is_Inactive` has rich *element* descriptions but no flow-level `<description>`.

**Trigger-context map for Account (the core problem):**
- **Before-save:** `Account_Update_Industry_Category` (1 flow ✔)
- **After-save:** `Account_Object_Create_Edit_1` **+** `Account_is_Inactive` → **two flows in one context** ✗ (violates one-flow-per-trigger-context; execution order between them is non-deterministic unless explicitly ordered)
- **Legacy:** inactive `Account_Object_Create_Edit` Process Builder still deployed ✗

---

## Phase 3 — Deep analysis (active Account-context flows + subflow)

### 3.1 `Account_Object_Create_Edit_1` (active v10, RecordAfterSave, API 60) — the centrepiece

**A) What it does (plain English).** This is the catch-all automation for Accounts, migrated wholesale from the old "Account Object - Create/Edit" Process Builder ("All Account Processes are handled here"). On every create/update it walks a chain of decisions and, depending on what changed, it: stamps a sales-tax country code (via a subflow), flags/unflags Bad Debtor, copies Billing address into a blank Shipping address, pushes firm-level data down to Office accounts, derives two industry roll-up fields, and — on a 2-minute scheduled path — cascades the Ultimate Account onto related Contacts, Opportunities, Quotes, Orders, Contracts, Subscriptions and Interactions.

**B) Decision branches.**
- `myRule_1` *Check Disable Processes* — if `$Setup.Application_Settings__c.Disable_Process_Builders__c` is true, ends (kill-switch ✔). Else → `myRule_3`.
- `myRule_3` *Tax Code* — if new OR `BillingCountry` changed → calls subflow `Update_Tax_Country_Code` → `myRule_5`.
- `myRule_5` *Bad Debtor* — if `Debtor_Status__c` ∈ {Problem Debtor, Bad Debtor} (and record changed to meet) → set `Bad_Debtor__c = true` → `myRule_7`.
- `myRule_7` *Good Debtor* — if `Debtor_Status__c = Good Debtor` → set `Bad_Debtor__c = false` → `myRule_9`.
- `myRule_9` *Update Shipping Address* — if all 5 Shipping fields null → copy from Billing → `myRule_11`.
- `myRule_11` *Push Information to Office* — if RecordType **DeveloperName** = Office AND (Industry/Revenue/Employees/OrgType null) → pull those from Ultimate Account → `Check_if_record_is_office_or_firm`.
- `Check_if_record_is_office_or_firm` — if RecordType **Name** = Firm AND `PO_Required__c` changed → update child office records' `PO_Required__c` → `Check_if_industry_is_changed`.
- `Check_if_industry_is_changed` — if `Industry` changed OR new → `Check_Industry`.
- `Check_Industry` — Part1/Part2 (two formulas, split only because the `CASE` exceeds size limits) → set `Industry_Level_One__c`.
- **Scheduled path** `Mass_Update_Related_Records` (offset +2 min, batch 15) → `myRule_18`: if not-new AND `Ultimate_Account__c` changed → 7 sequential related-list updates.

**C) Data operations.** 14 DML elements. Same-record field sets on `$Record`: Bad Debtor (×2), Shipping copy, Push-to-Office field set, Industry Level One (×2). Related-record updates: child Office accounts (filtered `Ultimate_Account__c = $Record.Id`); and 7 related collections in the scheduled path. The subflow adds a further Account SOQL + Tax_Code__mdt SOQL + Account DML. **Bulkification:** no SOQL/DML in loops (no loops). However the related-list updates operate on `$Record.Contacts`, `$Record.Opportunities`, etc. — unbounded child collections.

**D) Dependencies / knock-on.** Each same-record update re-enters the Account save (recursion potential — partly mitigated by self-limiting criteria and `doesRequireRecordChangedToMeetCriteria`). Writing `$Record` in after-save means an **extra DML per save** on top of the user's. Cascade updates fan out to 7 child objects, each firing *their own* triggers/flows/roll-ups (e.g., Opportunity has 27 active validation rules + flows). Co-resident with `Account_is_Inactive` in the same after-save context. Also overlaps the standalone `AccountTrigger` Apex (API 64).

**E) Issues.**
- **CRITICAL — same-record updates in after-save.** Tax code, Bad Debtor, Shipping copy, Push-to-Office and Industry Level One all set fields on the triggering Account. Per Salesforce's Architect's Guide these belong in a **before-save** flow (no extra DML, no recursion, ~10× faster). Today each is a separate save-reentrant DML.
- **CRITICAL — zero fault paths** on all 14 DML elements and the subflow call.
- **CRITICAL — unbounded related-record DML.** The scheduled path updates entire child collections (`$Record.Contacts`, `…Opportunities`, etc.). A parent/ultimate account with thousands of children risks the 10,000-row DML limit and long scheduled-path execution.
- **HIGH — redundant subflow SOQL** (see 3.4).
- **HIGH — hardcoded picklist values.** ~100 industry strings and debtor statuses are inline in formulas; any picklist relabel silently breaks the mapping. Should be Custom Metadata-driven.
- **MEDIUM — RecordType reference inconsistency.** `myRule_11` uses `RecordType.DeveloperName` (correct) but `Check_if_record_is_office_or_firm` uses `RecordType.Name` (label — fragile/translatable).
- **MEDIUM — migration-artifact naming** (`myRule_1/3/5/7/9/11/18`). Element *labels* are meaningful, internal *names* are not.
- **MEDIUM — split industry logic** (Part1/Part2) and a **second** industry taxonomy in flow #3 (see below).
- **LOW — no flow-level documentation of the scheduled path's intent / batch sizing rationale.**
- **BUSINESS CONTEXT NEEDED:** Is the after-save cascade intentionally asynchronous (2-min delay)? What is the realistic max child-record count per ultimate account?

### 3.2 `Account_is_Inactive` (active v2, RecordAfterSave, API 56)

**A)** When an Account's `Status__c` becomes `Inactive`, it finds all related Contacts and stamps `LID__No_longer_at_Company__c = "Not at Company"` so downstream (LinkedIn/Sales Nav) treats them as having left.

**B)** No decisions. Entry filter only: `Status__c = Inactive`.
**C)** 1 Get (all Contacts where `AccountId = $Record.Id`, all fields auto-stored), a loop assigning the flag into a collection, then **one** bulk `Update_Contacts` after the loop. **DML is correctly outside the loop — bulkified.**
**D)** Updating contacts fires Contact triggers/flows (e.g., `Update_Account_Organisation_Type…`, `Gong…`). Co-resident with #1 in after-save.

**E) Issues.**
- **CRITICAL — no fault path** on `Update_Contacts`.
- **HIGH — no entry-change criteria.** The start filter is `Status__c = Inactive` with no `ISCHANGED`/"changed to meet criteria". The flow therefore re-runs and re-flags **every** time any field on an already-inactive account is edited — wasteful and overwrites any manual contact correction. Add `doesRequireRecordChangedToMeetCriteria` / `ISCHANGED(Status__c)`.
- **HIGH — API 56**, and the flow is **2 versions behind its own latest** (rolled back to v2).
- **MEDIUM — `Get_Contacts` retrieves all fields** (`storeOutputAutomatically`) when only Id + the flag are needed.
- **MEDIUM — no kill-switch** (inconsistent with #1 and the subflow).
- **BUSINESS CONTEXT NEEDED:** Is re-flagging on every save intended, or should it fire only on the Active→Inactive transition?

### 3.3 `Account_Update_Industry_Category` (active v4, RecordBeforeSave, API 62)

**A)** Before save, derives `Industry_Category_txt__c` from an override field, or from `Industry_ALM__c` + attorney count (Law Firm sizing), or a ~30-branch `CASE` mapping ALM industries to broad categories.
**B)** No decision elements — logic is in the `IndustryCategory` formula. Entry: any of Industry_Data_Provider/Industry_Category_Override/Industry_ALM changed and not-null (`OR` logic).
**C)** Single before-save `$Record` field set — **no DML, ideal pattern.**
**E) Issues.**
- **HIGH — hardcoded picklist mapping** (~30 ALM industries + size thresholds inline). Move to Custom Metadata.
- **MEDIUM — overlaps #1's industry logic.** #1 derives `Industry_Level_One__c` (different field, different taxonomy) from the standard `Industry`; this derives `Industry_Category_txt__c` from `Industry_ALM__c`. Two parallel industry-classification systems on the same object. **BUSINESS CONTEXT NEEDED:** are both fields actively consumed?
- **MEDIUM — no kill-switch.**

### 3.4 `Update_Tax_Country_Code` (active v2, Autolaunched subflow, API 49)

**A)** Given an Account Id, looks up the Account's `BillingCountry`, finds the matching `Tax_Code__mdt`, and writes `Sales_Tax_Country_Code__c` back to the Account (blank if no match).
**B)** `Check_Disable_Processes` (kill-switch on `Disable_Autolaunch_Lightning_Flow__c`); `CheckIfNull` (blank vs set tax code).
**C)** 2 Gets (Account by Id; Tax_Code__mdt by country) + 2 Account DML (set / blank).
**E) Issues.**
- **CRITICAL — no fault paths** on either DML or lookup.
- **HIGH — redundant SOQL + DML.** It is called from #1's after-save with the Account Id, then **re-queries the same Account** for `BillingCountry` (already on `$Record`) and **DMLs it again**. Folding this into #1 as a **before-save** field set (with a metadata Get) removes 1 SOQL + 1 DML per save entirely.
- **HIGH — API 49** (oldest in the set).
- **MEDIUM — inconsistent kill-switch field** (`Disable_Autolaunch_Lightning_Flow__c` vs #1's `Disable_Process_Builders__c`).

### 3.5 Incidental Account-writers (active)

- **`Lead_AL_UpdateGenericFields`** (autolaunched, API 64): **CRITICAL hardcoded Campaign Id** `701Px00000Vp6HkIAJ`; 6 DML, **no fault paths**. Writes Account data from Lead context.
- **`Update_Account_Organisation_Type_from_Contact_Organisation_Type`** (Contact after-save, API 52): cross-object Account update, **no fault path**; old API.
- **`Quote_BeforeSave_UpdateQuoteFields`** (API 65): **hardcoded RecordType Id** `0126g000000Om7TAAS` (before-save, no DML).
- **`Check_Completeness_of_Contact_Roles`**, **`UltimateAccountBeforeSaving`**, **`Entitlement_Flow`**: before-save readers of Account; main flags are old API (49/57) and inline complexity. No DML risk.

### 3.6 Inactive (deployed but off)
`Account_Object_Create_Edit` (legacy PB, API 49), `Task_AL_FirmUpdate` (hardcoded RecordType Id), `Gong_Conversations_Create_Edit` (hardcoded RecordType Id), `UltimateAccountBeforeSavingLead`. Runtime risk low; all are **tech-debt / cleanup** candidates and several would ship critical issues if reactivated as-is.

### 3.7 Positives worth keeping
- No SOQL/DML inside loops anywhere in the Account set.
- `Account_is_Inactive` correctly bulkifies its contact update.
- `Account_Object_Create_Edit_1` and `Update_Tax_Country_Code` both implement kill-switches (just inconsistently named).
- `Account_Update_Industry_Category` is a model before-save same-record flow.

---

## Phase 4 — Target architecture

**Salesforce recommended pattern:** one orchestrator flow per object per trigger context, routing via decisions to single-purpose autolaunched subflows, each guarded by a Custom Metadata feature toggle.

```
Account (target state)
├── Account_Trigger_BeforeSave  (RecordBeforeSave, Create+Update)   ← all same-record field updates
│   ├── [toggle] Sub_SetTaxCountryCode          (Get Tax_Code__mdt; set Sales_Tax_Country_Code__c)
│   ├── [toggle] Sub_SetDebtorFlag              (Bad_Debtor__c from Debtor_Status__c)
│   ├── [toggle] Sub_CopyBillingToShipping      (when shipping blank)
│   ├── [toggle] Sub_DeriveIndustryLevelOne     (CMDT-driven map → Industry_Level_One__c)
│   └── [toggle] Sub_DeriveIndustryCategory     (CMDT-driven map → Industry_Category_txt__c)
├── Account_Trigger_AfterSave   (RecordAfterSave, Create+Update)    ← cross-object / related-record work
│   ├── [toggle] Sub_InactiveAccountContactSuppression  (ISCHANGED(Status) → flag contacts)
│   ├── [toggle] Sub_PushFirmDataToOffices             (firm → child office accounts)
│   └── [toggle] Sub_CascadeUltimateAccount (async)    (Ultimate_Account__c → children, paginated)
└── Account_Trigger_BeforeDelete (RecordBeforeDelete)  ← create only if a delete rule emerges (none today)
```

Supporting: **`Flow_Feature_Toggle__mdt`** (one record per subflow: `Is_Active__c`, plus a global `Disable_All__c`), replacing the three different `Application_Settings__c` checkbox kill-switches. **`Industry_Mapping__mdt`** and **`Tax_Code__mdt`** (exists) to remove hardcoded picklist strings. RecordType references via DeveloperName only.

**Current → target mapping**

| Current | Becomes | Notes |
|---|---|---|
| `Account_Object_Create_Edit_1` › Tax Code branch + `Update_Tax_Country_Code` | `Sub_SetTaxCountryCode` (before-save) | Drop the re-query + extra DML; merge subflow logic in |
| …Bad/Good Debtor branches | `Sub_SetDebtorFlag` (before-save) | |
| …Shipping branch | `Sub_CopyBillingToShipping` (before-save) | |
| …Industry Part1/Part2 | `Sub_DeriveIndustryLevelOne` (before-save) | CMDT-driven; single element |
| `Account_Update_Industry_Category` | `Sub_DeriveIndustryCategory` (before-save) | CMDT-driven |
| …Push-to-Office branch | `Sub_PushFirmDataToOffices` (after-save) | cross-object → stays after-save |
| …Scheduled `myRule_18` cascade | `Sub_CascadeUltimateAccount` (after-save, async) | add pagination + fault paths |
| `Account_is_Inactive` | `Sub_InactiveAccountContactSuppression` (after-save) | add `ISCHANGED(Status__c)` + fault path |
| `Account_Object_Create_Edit` (PB) | **Delete** | dead duplicate |
| `Sample_Flow_to_Debug` | **Delete** (pending confirmation) | orphaned debug artifact |

**Should NOT migrate / handle separately**
- `Lead_AL_UpdateGenericFields`, `Update_Account_Organisation_Type…`, `Quote_BeforeSave…`, etc. are **other objects'** trigger flows — they belong to *those* objects' orchestrators, not Account's. They only need their own fixes (hardcoded IDs, fault paths).
- The unbounded `Cascade Ultimate Account` may be better as **Apex** (batchable, governor-safe) if child volumes are large — decide after the BUSINESS CONTEXT volume question.
- The standalone `AccountTrigger` Apex must be reconciled with the master flows (define order of execution) — out of scope for flow-only migration but flagged.

---

## Phase 6 — Test plan for the agreed top 3 changes

> Proposed top 3 (see roadmap for full ranking): **(1)** add fault paths across active Account DML flows; **(2)** add `ISCHANGED(Status__c)` entry criteria to `Account_is_Inactive`; **(3)** move Tax Code into before-save and retire the re-query subflow.

### Change 1 — Add fault paths (Account_Object_Create_Edit_1, Account_is_Inactive, Update_Tax_Country_Code, Update_Account_Organisation_Type…)
- **Scenarios:** (a) normal save still succeeds; (b) force a DML failure (e.g., a validation rule blocks the child update) and confirm the fault path surfaces a friendly error / logs rather than an unhandled `FLOW_ELEMENT_ERROR`; (c) bulk update 200 accounts via Data Loader — no partial silent failures.
- **Data:** 1 standard account; 1 account whose child contact would violate a contact validation rule; a 200-account CSV.
- **Before vs after:** before = unhandled flow error screen / silent rollback; after = controlled fault handling + (optional) error record.
- **Rollback:** redeploy prior active version (captured in `force-app` + git baseline); fault paths are additive so deactivation is low-risk.

### Change 2 — `ISCHANGED(Status__c)` on `Account_is_Inactive`
- **Scenarios:** (a) Active→Inactive flips contacts to "Not at Company" (still works); (b) edit a *different* field on an already-inactive account → flow does **not** re-fire / does not overwrite a manually corrected contact; (c) Inactive→Active → no contact changes.
- **Data:** inactive account with one contact whose flag was manually cleared.
- **Before vs after:** before = every edit re-stamps all contacts; after = only the status transition does.
- **Rollback:** redeploy v2 (current active) from git baseline.

### Change 3 — Tax code to before-save; retire subflow re-query
- **Scenarios:** (a) new account with BillingCountry = known country → correct `Sales_Tax_Country_Code__c` with **no** post-save update (verify via debug log: one save, no extra Account DML); (b) BillingCountry with no `Tax_Code__mdt` → field blanked; (c) BillingCountry changed on existing account → recalculated; (d) bulk 200 — one metadata Get, no per-record Account re-query.
- **Data:** Tax_Code__mdt rows for ≥2 countries + one unmapped country; 200-account CSV mixing mapped/unmapped.
- **Before vs after:** before = 1 extra SOQL + 1 extra DML per account (after-save subflow); after = zero extra SOQL/DML (before-save field set).
- **Rollback:** the before-save subflow is toggle-gated; disable the toggle and re-enable the `myRule_3` branch + subflow (git baseline) to revert.

---

*All findings above are read-only observations. No flow, metadata, or org configuration was modified during this audit.*
