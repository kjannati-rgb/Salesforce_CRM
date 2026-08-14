# Phase A Findings — World-Class Lead Conversion

**Companion to:** `ClaudeCode_Brief_Lead_Conversion.md`
**Pass:** read-only discovery on **LBR_PROD** (`kamyar.jannati@lbresearch.com`), 2026-06-08
**Status:** analysis only — nothing built or deployed. Build/deploy target remains **KJDEV**.
**Temp retrieves:** `C:\sf-work\_phaseA*` (outside the repo; working tree untouched).

---

## 0. Headline reframe (changes the build plan)

Two assumptions in the brief do not survive contact with production:

1. **Nothing in the org calls `Lead.convert()` except the standard native action.** None of the Pardot flows convert — they only *react* to a convert that already happened. There is exactly **one** real conversion mechanism (native convert), reached from both "doors."
2. **The engine room is almost entirely third-party managed packages.** Their code is not retrievable and not editable — only configurable. There is **no custom Apex trigger framework** on Lead/Contact/Account to "extend." The real extension surface is **flows** (+ optionally one new handler), and the real hazard is colliding with **DupeBlocker** and the **AddressTools `Validate*BeforeSave`** triggers mid-convert.
3. **There is NO existing account-matching / lead-routing engine.** The `LF` namespace is **Lead Forensics** (website-visitor identification), not LeanData. So the match-and-select service is greenfield — nothing to collide with on the matching side. ZoomInfo enriches but does not assign lead→account for conversion.

---

## 1. Address-stamp condition

**Where:** `Contact_Object_Create_Edit` flow → element `Update_Address`. After-save Contact, `CreateAndUpdate` trigger.
**Live version:** active = **v7**; latest = v8 (Draft). v7's live metadata was fetched via Tooling API and is **identical** to v8 — so the logic below is what runs in production.

**What it does** — sets `MailingCity / MailingCountry / MailingPostalCode / MailingState / MailingStreet` + `Phone` from the Account, via **fill-blanks** formulas:

```
var_street   = IF( ISBLANK(MailingStreet),     Account.BillingStreet,     MailingStreet )
var_city     = IF( ISBLANK(MailingCity),       Account.BillingCity,       MailingCity )
var_country  = IF( ISBLANK(MailingCountry),    Account.BillingCountry,    MailingCountry )
var_state    = IF( ISBLANK(MailingState),      Account.BillingState,      MailingState )
var_postcode = IF( ISBLANK(MailingPostalCode), Account.BillingPostalCode, MailingPostalCode )
var_phone    = IF( ISBLANK(Phone),             Account.Phone,             Phone )
```

**When:** the element sits on the flow's default path so it evaluates on essentially every create/edit, but because each formula only overwrites a **blank** Mailing field, it effectively stamps on **Contact insert** (`ISNEW`) and whenever a Mailing field is empty. On native convert the new Contact is `ISNEW` with blank Mailing fields → it **inherits the Office Account's billing address**.

A separate firm-stamp (`Ultimate_Parent__c`) is gated by:

```
var_checkforaccount = AND( OR( ISNEW(), ISCHANGED(AccountId) ),
                           NOT( ISBLANK( Account.Ultimate_Account__c ) ) )
```

**Implication:** confirmed — a wrong target Office (Account) propagates a wrong contact address at convert time. There is **no** address-named flow and **no** Contact-trigger stamp; this single flow element is the only fence point. Any reparent must snapshot/verify the Office before it fires.

---

## 2. Order-of-execution map (both doors converge)

Both doors are the same native convert. The Pardot door adds a pre-step (an SDR working a `Pardot_Form_Completion__c` record) and post-steps (back-linking). On `Lead.convert()` the platform inserts/updates **Account → Contact → (optional) Opportunity**, each firing its full automation stack:

| Stage | Fires (▲ = managed package, not editable) | Rejection / recursion risk |
|---|---|---|
| **Account** ins/upd | ▲ `ValidateAccountBeforeSave` (AddressTools/pw_cc), ▲ `DB_AccountTrigger` (DupeBlocker / CRMfusionDBR101), ▲ `AccountTrigger`/`OpsosAccountTrigger` (ZoomInfo DOZISF, Cvent, Sales Navigator LID), `AccountBefore`, `AccountParentFixer` (ParentFixer CRMfusionAPR), `normalizePersonAccountPhone`, `PS_Account` | **AddressTools can reject invalid address; DupeBlocker can block as duplicate → convert fails mid-flight** |
| **Contact** ins | ▲ `ValidateContactBeforeSave` (AddressTools/pw_cc — validates/standardizes the address being saved), ▲ `DB_ContactTrigger` (DupeBlocker), ▲ ZoomInfo/Groove normalize triggers → **after-save: `Contact_Object_Create_Edit` ⇒ ADDRESS STAMP fires here** | AddressTools / DupeBlocker reject; address stamp inherits Account billing — must be AddressTools-valid |
| **Lead** upd | ▲ `ValidateLeadBeforeSave` (AddressTools/pw_cc), ▲ `DB_LeadTrigger`, ▲ Lead Forensics `trgCopyVisit` / `trgCopyVisitExistingAccount` (LF — website-visit association, **not** account matching), `LeadListener` (Adobe Sign echosign_dev1) → after-save `Lead_AfterUpdate_MasterFLow` (subflow field updates, kill-switch gated) | |

**Pardot post-convert chain** — all after-save, fire once `Lead.IsConverted` flips:

```
Lead.convert()  →  Lead.IsConverted = TRUE
   →  Pardot_Form_Completion__c.Lead_Converted__c   (FORMULA = Lead__r.IsConverted = TRUE)  flips true
   →  Move_Lead_to_Contact_on_Pardot_Form  (after-save; filter Lead_Converted__c=true AND Contact__c empty)
          stamps  Contact__c = Lead__r.ConvertedContactId ,  clears Lead__c
   →  On_Pardot_Form_Creation  (after-save; on Contact__c / Lead__c change)
          stamps  Account_Contact__c = Contact__r.Account.Id ,  Campaign__c ,  Name
```

**Kill switches (custom setting `Application_Settings__c`):**
- `Disable_Autolaunch_Lightning_Flow__c` — gates `Lead_AfterUpdate_MasterFLow` and the obsolete `UltimateAccountBeforeSavingLead`.
- `Disable_Process_Builders__c` — gates `Contact_Object_Create_Edit`.

---

## 3. `Move_Lead_to_Contact_on_Pardot_Form` — convert or relink?

**Relink, not convert.**

- Flow on `Pardot_Form_Completion__c`. Active = **v2 (after-save)**; latest = Draft v4 (before-save) — substance identical.
- Filter: `Lead_Converted__c = true AND Contact__c = empty`.
- Single action: `Contact__c = Lead__r.ConvertedContactId`, then clear `Lead__c`.
- **No `convert()`, no record creation, no campaign / opportunity / lead-source handling.**

**The convert button is the standard native action.** There is **no custom Convert WebLink or quick action on Lead** (verified — zero rows). So opportunity/campaign behaviour is whatever native convert produces; the Pardot layer only joins the form record to the resulting Contact afterward.

---

## 4. `UltimateAccountBeforeSavingLead` — reuse / rebuild / discard?

**Discard.**

- Status = **Obsolete** (no active version — fully off; apiVersion 49).
- It was **never a matcher**: it requires `Lead.Account__c` to *already* be populated, then copies that Account's `Ultimate_Account__c` onto `Lead.Ultimate_Account__c`. No domain/company resolution. Kill-switch gated.
- Disabled because it is superseded boilerplate, not because the matching logic was risky (there was none).

**But it reveals the data model the new service should target** (Office-under-Firm is already wired in fields):

| Concept (brief) | Field in org |
|---|---|
| Office (convert target) | the `Account` record itself |
| Firm (rollup) | `Account.Ultimate_Account__c` |
| Lead → account link | `Lead.Account__c` (lookup) |
| Contact → firm | `Contact.Ultimate_Parent__c` |
| Form → resolved account(s) | `Pardot_Form_Completion__c.Account_Lead__c` / `Account_Contact__c` |
| Convert signal on form | `Pardot_Form_Completion__c.Lead_Converted__c` (formula on `Lead__r.IsConverted`) |

---

## 5. Items to steer Phase B/C before any code

1. **No existing matcher to fight (greenfield).** `LF` = **Lead Forensics** (website-visitor ID), not LeanData; `trgCopyVisit*` associate visit records, they do not match leads to accounts. ZoomInfo (DOZISF) enriches but does not assign the conversion account. So the `@InvocableMethod` match-and-select service is net-new — no routing engine to coordinate with.
2. **AddressTools (ProvenWorks, `pw_cc`) actively validates/standardizes addresses on save** via `Validate{Lead,Contact,Account}BeforeSave`. The address-stamp copies `Account.Billing*` → `Contact.Mailing*`; AddressTools then validates that result on the Contact insert. **The stamped address (and any reparent) must produce AddressTools-valid values (ISO Country/State picklists) or the convert/save can be rejected.** This is the concrete shape of the brief's "handle a `Validate*BeforeSave` rejection" test — and we can only catch/observe it, not edit it.
3. **DupeBlocker (`CRMfusionDBR101`) can block the Account/Contact insert as a duplicate mid-convert.** Our match-first approach should *reduce* these (convert into the existing Office rather than creating a dup), but the failure path must be handled.

### Authoritative namespace → package map (verified via InstalledSubscriberPackage)

| Namespace | Package | Role |
|---|---|---|
| `LF` | **Lead Forensics** | Website-visitor identification (NOT routing/matching) |
| `pw_cc` | **AddressTools Free** (ProvenWorks) | Address validation/standardization (`Validate*BeforeSave`) |
| `CRMfusionDBR101` | **DupeBlocker** | Duplicate prevention (`DB_*Trigger`) — can reject inserts |
| `CRMfusionAPR` | **ParentFixer** | Account hierarchy (`AccountParentFixer`) |
| `DOZISF` | **ZoomInfo** | Enrichment / OpsOS (`Opsos*Trigger`, `*Trigger`) |
| `pi` | **Pardot** | Marketing automation (`LogLeadChange`/`LogContactChange`) |
| `LID` | **Sales Navigator for SFDC** | LinkedIn (`*Trigger`, `No_longer_at_Company__c`) |
| `Validity_Verify` | **Validity BriteVerify** | Email verification |
| `DaScoopComposer` | **Groove** | Sales engagement (`normalize*Phone`) |
| `rh2` | **Rollup Helper** | Field rollups (`PS_*`) |
| `echosign_dev1` | **Adobe Acrobat Sign** | E-signature (`LeadListener`) |
| `CventEvents` | **Cvent** | Events (`*Trigger`) |

---

## Appendix — flow status snapshot (active vs latest)

| Flow | Object / type | Active ver | Latest ver | Notes |
|---|---|---|---|---|
| `Contact_Object_Create_Edit` | Contact, after-save | v7 (Active) | v8 (Draft) | Address stamp; v7≡v8 |
| `Move_Lead_to_Contact_on_Pardot_Form` | Pardot form, save | v2 (Active, after-save) | v4 (Draft, before-save) | Relink only |
| `On_Pardot_Form_Creation` | Pardot form, after-save | Active | — | Stamps Account_Contact__c / Campaign |
| `Pardot_Lead_Conversion` | screen/action Flow (button) | Active | — | Back-link + navigate; no convert |
| `Lead_AfterUpdate_MasterFLow` | Lead, after-save | Active | — | Orchestrator; subflow field updates |
| `Account_Object_Create_Edit_1` | Account, after-save | **Obsolete** | — | Not running |
| `UltimateAccountBeforeSavingLead` | Lead, before-save | **none (Obsolete)** | — | Discard |
| `Pardot_Form_completion_Create_task...` | Pardot form | Active | — | Task creation (not analysed in depth) |

> **Correction note (2026-06-08):** an earlier draft of this doc labelled the `LF` namespace "LeanData" and `pw_cc` a generic "Validate" tool. Verified against `InstalledSubscriberPackage`: `LF` = **Lead Forensics**, `pw_cc` = **AddressTools (ProvenWorks)**. See §5 for the full map.
