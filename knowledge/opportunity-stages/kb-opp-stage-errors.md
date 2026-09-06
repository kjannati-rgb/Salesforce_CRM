---
title: Opportunity Stages — error message index
owner: Kamyar Jannati (Head Data and CRM)
review-date: 2027-01-04
verified-against:
  - PROD retrieve 2026-07-04: all 41 Opportunity validation rules (31 active), flows Check_Completeness_of_Contact_Roles, Opp_Error_Saleshandshake, Opportunity_BeforeSaveFlow, Renewal_Justification_Validation, Update_Opportunity_Contract_Attached_Field, Opportunity v27 (active auto-submit flow), approvalProcesses Opportunity.*
---

# Opportunity stage errors — what they mean and how to resolve them

Look the error up by its exact wording. "Raise a case" means the situation needs the CRM team.

## Errors when trying to close won

**"Sales Rep cannot move the Opportunity to Closed Won. Please "Submit for Approval"."** / **"You cannot close an Opportunity directly. Please "Submit for Approval"."**
You tried to set Closed Won directly. Move the stage to *Closed Won – Pending Approval* instead — the approval is then submitted automatically (despite what the error text implies, no button click is needed), and Finance approval closes the opportunity for you.

**"Please attach signed contract before pushing opp for approval"**
The opportunity has no qualifying signed contract yet. Attach one — either complete the e-signature agreement (Adobe Sign) or upload the signed contract / email confirmation to the opportunity — then save again; automation ticks the `Contract Attached` box for you once a qualifying document is on the record. If the signed document is already attached and the error persists, raise a case.

**"Please send out the contract to sign or attach the necessary document before proceeding to close"**
Same contract check, at the *Contract Out* stage — attach the signed contract or complete the e-sign agreement; the box is ticked automatically.

**"Approved Primary Quote is required for Opportunity stage "Closed won – pending approval". Please check if Opportunity Product exists."**
The opportunity needs products/line items and its primary quote must be in approval status *Approved*. If your quote is still in approval, wait for it; if no quote is primary, mark one primary.

**"You have open Complete Success Plan tasks on this opportunity. Please complete them before closing the opportunity."**
Complete (or have the owner complete) the open Complete Success Plan tasks first.

**"Online/Card Payment Reference is required as Quote Payment Type is Payment Already Made Online."**
The primary quote's payment type is POS — enter the Online/Card Payment Reference on the opportunity.

**"Please add Top ID before pushing opp to 'Closed Won - Pending Approval'"**
ALM deals need the Top ID field filled before this stage.

**"Please complete "<field name>" in the Sales Handshake before progressing the opportunity"**
Your deal is flagged for a Sales Handshake (LexPro / content subscription / benefitting-group product) and the named field on the Sales Handshake record is empty. Open the Customer Journey / Sales Handshake record, complete that field, and retry the stage change.

**"For Auto-Renewal opportunities, you must send the renewal email and tick the 'Renewal Email Sent' checkbox before progressing to Closed Won - Pending Approval."**
Send the renewal email and tick `Renewal Email Sent` first.

**"Please make sure the Account has an associated Ultimate Account before proceeding."**
The account is missing its Ultimate Account (firm-level parent). Set it on the Account, or raise a case if you don't have access.

**"Please enter a valid Lead Source"**
New Business deals at ≥90% probability need Lead Source filled.

## Errors when trying to close lost

**"Please complete both Closed Lost Primary Reason and Note before marking this opportunity as Closed Lost."**
Fill `Closed Lost Primary Reason` and `Note`. Applies to Practice Intelligence, Market Intelligence, and MBL Seminars teams.

**"Please select a closed lost sub reason"**
Your chosen primary reason requires a sub reason as well.

**"Please enter the name of the competitor"**
Primary reason is "Client chose competitor" — name the competitor.

## Errors moving between open stages

**"To move opportunity stage from Identify, please add products."**
Users on the Expert Insight price books must add opportunity products before leaving Identify.

**"Complete the three LexPRO qualification answers (Jurisdiction, Content, and Process) before moving this New Business deal past Identify…"**
Lexology Pro New Business deals: run the "Qualify this deal" action and answer all three, or set Closed Lost to disqualify.

**"This Opportunity needs a complete primary Contact Role before it can be saved at this win probability. Please provide: <missing items>."**
Above a configured probability, the primary Contact Role must be complete. The message lists exactly what's missing (e.g. email, phone, role). Fix those on the primary contact/role and save again. If you believe you need an exemption, raise a case (a bypass permission exists).

**"This Account on the Opportunity has been flagged by Finance as having a Debt…"**
Account is a Bad Debtor; deals at ≥50% probability are blocked. Contact invoicing@lbresearch.com to resolve, or close lost if the deal can't proceed.

**"Close Date must be in the future"**
Open opportunities can't be saved with a close date before today — update the Close Date.

**"Forecast Pending is used only by PI and Intelligence team"**
The Forecast Status "Forecast Pending" is restricted to specific teams; pick a different forecast status.

**"Sales made from Hong Kong cannot be processed in EUR currency…"**
Change the opportunity currency; HK-entity reps cannot sell in EUR.

**"Please enter an End User"** / **"If the "Purchased Via" is Direct, the end user must be left blank."**
Agency deals require an End User account; Direct deals must leave it blank.

## Errors on closed or locked records

**"Opportunity cannot be edited because it is Closed Won"** / **"…Closed Lost"**
Closed opportunities are locked. If a correction is genuinely needed, raise a case for the CRM/Finance team. (Cancellation-request fields remain editable on Closed Won records.)

**"Opportunity Line Items cannot be deleted because the Opportunity is closed."**
Line items on closed opportunities can't be removed — raise a case if a correction is required.

**"Opportunity owner cannot be changed, please contact Salesforce Admin"**
Owner changes are admin-only — raise a case with the business reason.

**"Opportunity is Locked. please contact your administrator"**
The record is flagged as deleted/locked — raise a case.

## Cancellation errors

**"Cancellations cannot be closed without approval."**
Don't set "Closed Won - Cancellation" manually. Put the opportunity at *Cancellation - Pending Review* — the approval is submitted automatically, and approval closes it.

## Creation-time errors

**"Opportunities classified as 'Repeat Business' or 'Auto-Repeat Business' must have a specified previous opportunity…"**
Link the previous opportunity, or contact CRM support.

**"Opportunities cannot be created or edited for Accounts based in sanctioned countries…"**
Compliance block — contact the Salesforce team if there is a legitimate compliance-cleared need.

## Quote-side errors during renewals

**"Please add Renewal Term Justification if …"** / **"Please add Special Terms if …"** (variants mentioning auto-renewal removed or renewal uplift less than 7.5%)
Raised when saving the renewal *quote*: uplift below 7.5% or removing auto-renewal requires the justification/special-terms fields on the quote.

---

*If an error message is not in this list, do not guess — create a case and include the exact error text, the opportunity ID, and what you were changing.*
