# Agent Topic: Opportunity Stages — Phase 0 Grounding Report

**Date:** 2026-07-04 · **Source of truth:** PROD metadata retrieve (snapshot in `agent-grounding/prod-opportunity-stages/`) + live SOQL counts. Per Standard v2 §1: metadata → article → agent. Nothing below comes from memory or generic Salesforce docs.

## What was retrieved

| Component | Count | Notes |
|---|---|---|
| CustomObject:Opportunity | 999 files | fields, 41 validation rules, 4 record types, 3 business processes |
| StandardValueSet:OpportunityStage | 1 | 10 active stage values |
| PathAssistant | 4 relevant | Default (__MASTER__), New_Business, Renewals, Cancellation — all active |
| Flows (stage-gating) | 10 | 6 active, 1 Draft, 2 Obsolete, 1 legacy WF |
| ApprovalProcess:Opportunity.* | 7 | 5 active, 2 inactive |
| Live SOQL | — | 599,130 Opps grouped by StageName confirm stage usage |

## Verified stage model

- Record types: **New_Business** and **Opportunity_Readonly** → "New Businesses" process; **Renewals** → "Renewals"; **Cancellations** → "Cancellations".
- New Business / Renewal live stages (identical lists): Identify (10%, Pipeline) → Qualify (20%, Pipeline) → Evaluate (50%, Best Case) → Negotiate (75%, Best Case) → Contract Out (90%, Most Likely) → Closed Won – Pending Approval (95%, Forecast, **en-dash**) → Closed Won (100%) / Closed Lost (0%).
- Cancellations: Cancellation - Pending Review (95%, Omitted) → Closed Won - Cancellation (100%, counts as won, Omitted from forecast).
- **"Evaluation" and "Close" are dead values**: still listed in both business-process definitions, absent from the active StandardValueSet, zero records in PROD. Cleanup candidate; excluded from user-facing articles.

## Verified gate inventory (active only)

**Validation rules — 31 active of 41.** Stage-relevant active gates: Add_products_to_the_opportunity, Bad_Debtor_Account_Flag, Cancellation_Requires_Approval, Close_Date_must_be_in_the_future, Closed_Lost/Won_cannot_be_edited, Closed_lost_primary/sub_reason, Contract_Not_Attached (Contract Out + CWPA), End_user_mandatory, Forecast_pending_valid_only_for_PI, HK_reps_cannot_sell_in_EUR, Lead_Source_Mandatory_for_Closing, LexPRO_NB_Qualification_Gate, Lock_deleted_opportunities, No_Deletes_Closed_OLI, Opportunity_cannot_be_Closed_Won_by_User, Opportunity_must_be_submitted_for_approv, Opportunity_owner_cannot_be_changed, Opp_With_Open_Complete_Success_Plan_Task, Payment_Already_Made_Online, Please_enter_the_name_of_the_competitor, Primary_Approved_Quote_Required, Require_Renewal_Email_For_Auto_Renewals, Sanctioned_Countries, Ultimate_Account_Mandatory_for_closing.

**Inactive (never cite as behaviour):** ALM_Top_ID (superseded by Opportunity_BeforeSaveFlow custom error), CS_Contact_Needed_to_Close_Win_NB_Renewa, Customer_Journey_Sales_Handshake_NB (superseded by Opp_Error_Saleshandshake flow), Next_Contact_Date_Mandatory, Only_Budget_Cut_Closed_Lost_reason, Opportunity_Account_Billing_Info, Opportunity_must_have_a_campaign, Pardot_form_shoulfd_be_linked_to_opp, Pricebook_Match_for_Closed_Won_Pending_R, USA_reps_can_close_deals_only_in_USD, Validate_Invoice_Contact_Account_ID. **Contact_Role_Complete_50 is deleted from PROD** (present only in the local repo).

**Flows that block saves (all Active in PROD):**
- `Check_Completeness_of_Contact_Roles` — before-save, entry StageName ≠ Closed Lost; CMDT-driven (`Contact_Role_Check_Setting__mdt`); dynamic error "This Opportunity needs a complete primary Contact Role…"; fail-open on fault; bypass via `$Permission.Bypass_Contact_Role_Check` or `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c`.
- `Opp_Error_Saleshandshake` — after-save update; fires when stage *changes to* Closed Won – Pending Approval AND (LexPro_present__c OR Content_Sub_Present__c OR Benefitting_Group_Product__c); 24 field-specific "Please complete … in the Sales Handshake" errors.
- `Opportunity_BeforeSaveFlow` — Top ID error at CWPA for ALM deals; also Invoice Contact checks at CWPA.
- `Renewal_Justification_Validation` — on **SBQQ__Quote__c**, not Opportunity: 6 error variants requiring Renewal Term Justification / Special Terms when uplift < 7.5% or auto-renewal removed.
- `Opportunity_Contact_Role_Check_for_Duplicate` — after-save, no custom error nodes in current PROD version (v9 idempotency fix status: see OCR duplicate project).

**Flow-status corrections vs assumptions:** `Update_Opp_Stage_to_Evaluation` is **Obsolete** (no auto-advance to Evaluate exists); `Opportunity_Approval_Process` flow is **Draft** (the live approval mechanism is the standard Approval Processes below); `Opportunity_Object_Create_Edit` workflow is Obsolete.

**Approval processes (5 active):** Finance_Approval_Process / _ALM / _ALM_Events — identical entry (stage = Closed won – pending approval, NOT Approved__c, NOT Submitted_to_Approval_Process__c, org bypass off); on final approval: Approved__c = true, stage → **Closed Won**, "Ordered" action. Finance_Approval_Process_Cancellation / _ALM_Events_Ca — entry stage = Cancellation - Pending Review; on approval stage → **Closed Won - Cancellation**. Inactive: Bad_Debtor_Approval_Process, Problem_Debtor.

## Latent defects found (spawned as separate fix task)

1. `Add_products_to_the_opportunity` — "**Negociate**" misspelled in CASE; never fires at Negotiate.
2. `Require_Renewal_Email_For_Auto_Renewals` — hyphen vs **en-dash** in stage literal; never fires at all.
3. `Opp_With_Open_Complete_Success_Plan_Task` — exempts profile "**System Administrator1**" (typo); real sysadmins not exempt.

## Cross-project dependency flag

`Closed_Won/Lost_cannot_be_edited`, `Opportunity_cannot_be_Closed_Won_by_User`, `Opportunity_must_be_submitted_for_approv`, `Lead_Source_Mandatory_for_Closing` are all conditioned on `$Setup.rh2__PS_Settings__c.rh2__Run_Validation_Rule__c` — **the rh2 (Rollup Helper) custom setting is a live dependency of the close-lock regime.** Add to the Firm Sales Summary rh2-decommission blocker list: removing rh2 settings would silently disable the close locks.

## Bypass / exemption standard (verified)

- Org-wide: `Application_Settings__c.Disable_Validation_Rules__c`, `.Disable_Approval_Processes__c`, `.Disable_Autolaunch_Lightning_Flow__c` (hierarchy custom setting — can be set per-user).
- Profile exemptions vary per rule; recurring: System Administrator, Custom: Fin/Ops/HR, ALM - Custom: Fin/Ops/HR, Custom: Data Management (close-directly only).
- Permission: `Bypass_Contact_Role_Check` (contact-role gate only).
- Close-lock rules additionally allow edits when only `Cancellation_Requested__c` / `Cancellation_Reason__c` change.

## Articles authored from this grounding

`knowledge/opportunity-stages/kb-opp-stage-model.md`, `kb-opp-closing-and-approval.md`, `kb-opp-stage-errors.md`. Frontmatter carries owner, review date, and the verified-against component list per Standard v2 §1.
