# Contact Consolidation — Phase 0 Diagnosis (DIAGNOSIS ONLY, no build)

**Date:** 2026-06-17
**Org:** LBR_PROD (`lawbusinessresearch.my.salesforce.com`, user `kamyar.jannati@lbresearch.com`) — PRODUCTION.
**Scope:** Four contact roles across Opportunity and CPQ Quote (`SBQQ__Quote__c`): **Primary, Invoice, Creative, Event Logistical**.
**Goal (CRO):** one entry point per contact; everything else derived. Fewer clicks, no drift.

> **Method note / correctness caveat.** Analysis ran against a fresh live retrieve from prod (247 flows + 3 Apex classes). **Flow active/inactive status was taken from the Tooling API (`SELECT Status FROM Flow WHERE Definition.DeveloperName = …`), NOT from the retrieved XML `<status>` tag.** Reason: `sf project retrieve` returns each flow's *latest* version, whose `<status>` can read `Obsolete`/`Draft` while an *earlier* version is the one actually Active. Two flows here are exactly that case (see Inventory). For any flow whose true active version ≠ latest, the active version's metadata was pulled directly via Tooling and read.

---

## 1. Field mapping (confirmed)

| Contact | Opp field | Quote field |
|---|---|---|
| Primary | `Primary_Contact__c` (+ unused std `ContactId`) | `SBQQ__PrimaryContact__c` (CPQ-managed) |
| Invoice | `Invoice_Contact__c` | `Invoice_Contact__c` |
| Creative | **(none — missing)** | `Creative_Contact__c` |
| Event Logistical | **(none — missing)** | `Event_Logistics_Contact__c` |

Out of scope but present: Opp `Production_Contact__c`, `Distribution_Contact__c`; Quote `Alternative_Production_Contact__c`, `Secondary_Contact__c`.

**Apex:** the three relevant classes (`OpportunityTriggerHandler`, `OpportunityBillingEntityHandler`, `OpportunityAnalyticsCreate`) contain **zero** references to any contact field or OpportunityContactRole. All custom contact logic is in flows; CPQ-managed triggers handle native primary-contact behaviour.

---

## 2. What populates each contact today (active automation only)

| Contact | Opp field — populated by | Quote field — populated by |
|---|---|---|
| **Primary** | **Source of truth = primary OpportunityContactRole** (native related list, manual; or screen flows below). `Opportunity_Contact_Role_Create` **v6 Active** (after-save on OCR, `CreateAndUpdate`, gated by `Disable_Process_Builders__c`) sets `OCR.Role="Decision Maker"` and **`Opp.Primary_Contact__c ← OCR.ContactId`**. So the Opp field is auto-synced from the OCR. | **CPQ-native** on new-quote creation (from Opp primary contact). On **Amendment** quotes, `Update_Primary_Contact_on_Amendment_Quote` **v1 Active** re-stamps `SBQQ__PrimaryContact__c ← Opp.Primary_Contact__c`. Also settable manually via `Quote_SubmitForApproval`. |
| **Invoice** | `Opportunity_BeforeSaveFlow` **v2 Active** (before-save) — **only at Stage = "Closed Won – Pending Approval", only if blank**: rule 1 `← Primary_Contact__c`; rule 2 `← SBQQ__PrimaryQuote__r.Invoice_Contact__c`. Otherwise manual. | **Manual only** via `Quote_SubmitForApproval` lookup. Nothing copies it from the Opp. `Quote_BeforeSave_UpdateQuoteFields` only denormalizes its email/phone for the template. |
| **Creative** | *(no field)* | **Manual only** via `Quote_SubmitForApproval` (shown when `ALM_Event_Product__c > 0`). Name/email denormalized by `Quote_BeforeSave_UpdateQuoteFields`. |
| **Event Logistical** | *(no field)* | **Manual only** via `Quote_SubmitForApproval` (shown when `ALM_Event_Product__c > 0`). Email denormalized by `Quote_BeforeSave_UpdateQuoteFields`. |

Orchestrators `Opportunity` (v27) and `Quote_AfterSave_MasterFlow` (v1) and their subflows write **none** of the in-scope fields (the Opp orchestrator only *reads* `Primary_Contact__c` to derive out-of-scope Distribution/Production contacts).

---

## 3. Flow inventory — true active status (Tooling API)

**Active (12):**
`Check_Completeness_of_Contact_Roles` (v5) · `Opportunity_BeforeSaveFlow` (v2) · `Opportunity` (v27) · `Opportunity_Contact_Role_Create` (v6) · `Opportunity_Contact_Role_Check_for_Duplicate` (v7) · `Add_Contact_Roles_on_Amendments` (v3) · `Update_Primary_Contact_on_Amendment_Quote` (v1) · `Quote_BeforeSave_UpdateQuoteFields` (v4) · `Quote_AfterSave_MasterFlow` (v1) · `Quote_SubmitForApproval` (v5) · `Clone_opportunity` (v19) · `Create_Opportunity_from_Campaign_Member` (v4)

**No active version (dead) (4):**
`Opportunity_Contact_Role_Create_Edit` · `Add_Contact_Roles_to_Opportunity` · `Opportunity_Object_Create_Edit` · `Update_Opportunity_fields`

> ⚠️ Two of the Active flows above (`Opportunity_Contact_Role_Create` v6, `Opportunity_Contact_Role_Check_for_Duplicate` v7) read as `Obsolete`/`Draft` in retrieved source because their *latest* version is dormant while an earlier version runs. Confirmed Active + logic verified against the live version.

`Opportunity_Contact_Role_Check_for_Duplicate` v7 (Active) **blocks** a second OCR with the same Opportunity+Contact(+Role): custom error *"This is an duplicate contact role, please use existing contact role."*

---

## 4. Data evidence (prod, 2026-06-17)

**Opp.Primary_Contact__c is genuinely auto-synced from the OCR:** of **19,116** open opps with a primary OCR, **19,112 (99.98%)** have `Opp.Primary_Contact__c` populated.

**Quote contact-lookup population:**

| Scope | Quotes | Primary | Invoice | Creative | Event |
|---|---|---|---|---|---|
| All quotes | 167,800 | 165,614 (98.7%) | 207 (0.1%) | 23 (0.01%) | 208 (0.1%) |
| ALM event quotes (`ALM_Event_Product__c>0`) | 438 | 352 (80%) | 202 (46%) | 23 (5%) | 203 (46%) |

Reading: Primary is near-universal (automated). Invoice/Creative/Event are **almost exclusively an ALM-Events concern** (202/207 Invoice, 203/208 Event, 23/23 Creative populated quotes are event quotes) and, even on event quotes, are captured **< half the time** (Invoice/Event 46%, Creative 5%). This is the manual-re-key friction, quantified.

---

## 5. Redundant / overlapping / conflicting writers

- **Primary contact lives in three stores but IS glued one-directionally:** OCR (source) → `Opp.Primary_Contact__c` (via `Opportunity_Contact_Role_Create` v6) → quote primary (CPQ native / amendment flow). No back-sync: editing `Opp.Primary_Contact__c` directly does **not** update the OCR (narrow drift edge).
- **Amendment quote primary** is sourced from `Opp.Primary_Contact__c` (kept current from OCR) — low-severity drift only if the Opp lookup was hand-edited.
- **`Opp.Invoice_Contact__c`** has two before-save rules, both gated to the same stage and both "if blank" — undocumented precedence (Primary-source vs Quote-source), low practical risk.
- **Dead clutter:** `Opportunity_Contact_Role_Create_Edit` and `Add_Contact_Roles_to_Opportunity` are superseded by the active v6 and should be removed to stop the architecture reading as if multiple things sync the OCR.

## 6. The Creative & Event gap
No Opp field exists for Creative or Event Logistical, so they can **only** live on the Quote, entered manually via `Quote_SubmitForApproval` (and only when an ALM event product is present). Nothing derives them; they cannot be "entered once on the Opp" today because the Opp has nowhere to store them. Data shows they're frequently left blank.

## 7. What `Check_Completeness_of_Contact_Roles` blocks (v5 Active)
Before-save on Opportunity, `CreateAndUpdate`, entry `StageName ≠ Closed Lost`. Raises a Custom Error when **ALL**:
1. `Probability ≥/> Min_Probability__c` (CMDT `Contact_Role_Check_Setting__mdt.Default`, inclusive per `Threshold_Inclusive__c`);
2. ≥1 required field missing;
3. user lacks `Bypass_Contact_Role_Check` custom permission;
4. `SBQQ__AmendedContract__c` is blank (**amendments exempt**);
5. stage not in `Excluded_Stages__c`.

Required = **a primary OCR must exist**; plus, per CMDT toggles, that Contact's `Email`/`Title`/`FirstName`/`MailingStreet`/`MailingCity` and the Account's `BillingStreet`/`City`/`Country`. It reads **OCR → Contact → Account** only — never `Opp.Primary_Contact__c` or any Quote field. Fails open on lookup fault; stamps `Has_Contact_Role__c` / `Has_Complete_Contact_Role__c` for CRM Analytics.

---

## 8. KEEP / RETIRE / ADD

**KEEP**
- `Check_Completeness_of_Contact_Roles` (v5) — single, CMDT-driven, bypass-aware, fail-open gate; the OCR is its source of truth.
- `Opportunity_Contact_Role_Create` (v6) — the OCR → `Opp.Primary_Contact__c` sync (load-bearing; 99.98% fill).
- `Opportunity_Contact_Role_Check_for_Duplicate` (v7) — dedup enforcement.
- CPQ-native quote primary; `Quote_BeforeSave_UpdateQuoteFields` denormalization (template depends on it); `Add_Contact_Roles_on_Amendments`; `Update_Primary_Contact_on_Amendment_Quote`.

**RETIRE** (genuinely dead; remove after confirming unreferenced)
- `Opportunity_Contact_Role_Create_Edit`, `Add_Contact_Roles_to_Opportunity` — superseded by the active v6.

**ADD** (next session, KJDEV-first)
- Treat Primary as already solved (OCR = single source → Opp field → quote, all automated). Do not rebuild it.
- Give Invoice/Creative/Event a single entry point on the **Opp**: add `Creative_Contact__c` + `Event_Logistics_Contact__c` lookups (Invoice already exists), then one after-save flow copies Opp → Quote on quote-create (twin-field), so reps enter once on the Opp and the quote inherits. Keep the `Quote_SubmitForApproval` lookups as override-only.
- Scope is effectively **ALM Events** — ~438 event quotes, contacts captured < half the time today. Right-size the build accordingly.

## 9. Open questions for review
- Should the single entry point for the three new contacts be Opp **lookups** or **OCR roles** (custom Role values)? Lookups are simpler; OCR roles align with the existing gate model.
- Creative at 5% capture even on event quotes — is it genuinely rarely needed, or under-captured? Confirms whether to automate it at all.
- Confirm there is no managed-package (SBQQ/sbaa/trumpet/DOZISF) behaviour that already moves these three onto the quote before building.
