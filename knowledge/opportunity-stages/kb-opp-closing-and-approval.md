---
title: Opportunity Stages — closing an opportunity (won, lost, cancellation)
owner: Kamyar Jannati (Head Data and CRM)
review-date: 2027-01-04
verified-against:
  - PROD retrieve 2026-07-04: Opportunity validation rules (41), approvalProcesses Opportunity.* (7), flows Opportunity_BeforeSaveFlow, Opp_Error_Saleshandshake, Check_Completeness_of_Contact_Roles, Update_Opportunity_Contract_Attached_Field, Opportunity v27 (active auto-submit flow)
---

# Closing an opportunity

## Closing Won — the approval route

Sales users cannot set an opportunity to **Closed Won** directly; two validation rules block it, by design. The route is:

1. **Move the stage to "Closed Won – Pending Approval".** Several checks must pass at this point (see below).
2. **The approval is submitted automatically.** As soon as the record saves at this stage, automation submits it to the correct Finance approval process for your team — you do not need to click "Submit for Approval". If the record does not appear in approval shortly after the stage change, raise a case.
3. **Finance approves.** On final approval the record is marked Approved, ordered, and the stage moves to **Closed Won** automatically. If rejected, fix what Finance flagged; re-entering the stage resubmits.

Only Finance/Ops profiles and System Administrators can set Closed Won manually.

### Checks that must pass at "Closed Won – Pending Approval"

- **Signed contract attached** — the `Contract Attached` box must be ticked, and **you normally don't tick it yourself**: at Contract Out and Closed Won – Pending Approval, automation checks the opportunity for a completed e-signature agreement (Adobe Sign) or an attached contract document (a manually uploaded signed contract or email confirmation) and ticks the box automatically. So if you see "Please attach signed contract before pushing opp for approval" (or, at **Contract Out**, "Please send out the contract to sign or attach the necessary document before proceeding to close"), the fix is to make sure the signed contract or confirmation is actually attached to the opportunity — or the e-sign agreement is completed — then save again. If it is attached and the error persists, raise a case.
- **Approved primary quote** — the opportunity needs line items and a primary quote with approval status Approved ("Approved Primary Quote is required…").
- **No open Complete Success Plan tasks** ("You have open Complete Success Plan tasks on this opportunity…").
- **Online payment reference** — if the primary quote's payment type is POS, the Online/Card Payment Reference field is required.
- **ALM deals: Top ID** — ALM opportunities need `Top ID` filled ("Please add Top ID before pushing opp to 'Closed Won - Pending Approval'"), and invoice-contact checks apply.
- **Sales Handshake complete** — for deals flagged as LexPro / content subscription / benefitting-group product, moving to this stage with an incomplete Sales Handshake raises a field-specific error ("Please complete "…" in the Sales Handshake before progressing the opportunity"). Complete the named field on the Sales Handshake (Customer Journey) record and retry.
- **Auto-Renewal email** — Auto-Renewal opportunities require the renewal email to have been sent and the 'Renewal Email Sent' box ticked.

### Checks at Closed Won itself (applied when approval completes or when an exempt profile closes manually)

- The Account must have an **Ultimate Account** ("Please make sure the Account has an associated Ultimate Account before proceeding").
- New Business deals at ≥90% probability need a **Lead Source**.

## Closing Lost

Any open opportunity can be set to Closed Lost. Requirements:

- **Practice Intelligence, Market Intelligence, and MBL Seminars teams** (New Business and Renewal forecast types): `Closed Lost Primary Reason` **and** `Note` are mandatory, and most primary reasons also require a `Closed Lost Sub Reason`.
- If the primary reason is **"Client chose competitor"**, the competitor's name is mandatory (all teams).

## Cancellations

- Create/use a **Cancellation** opportunity; it starts at **Cancellation - Pending Review** and requires approval — you cannot set "Closed Won - Cancellation" directly ("Cancellations cannot be closed without approval").
- The approval is **submitted automatically** when the record saves at Cancellation - Pending Review; on approval, the stage moves to Closed Won - Cancellation automatically and the close date is stamped.

## After an opportunity is closed

- **Closed Won and Closed Lost opportunities are locked** — edits are blocked for sales users ("Opportunity cannot be edited because it is Closed Won/Lost"). Exception: the cancellation-request fields can still be changed on a Closed Won opportunity, which is how you initiate a cancellation.
- **Line items on closed opportunities cannot be deleted.**
- **Opportunity owner changes are blocked** for everyone except admins, open or closed ("Opportunity owner cannot be changed, please contact Salesforce Admin").
- Finance/Ops profiles and System Administrators are exempt from the edit locks; if a closed record genuinely needs correcting, raise a case.

## Other blocks you can hit while progressing a deal

- **Products required to leave Identify** — for users on the Expert Insight price books (Lexology Panoramic / In-Depth / GXRs), the stage cannot leave Identify without opportunity products.
- **LexPRO qualification gate** — Lexology Pro team New Business deals cannot move past Identify (except to Closed Lost) until the three LexPRO qualification answers are complete; use the "Qualify this deal" action.
- **Primary Contact Role completeness** — above a configured win probability, saving requires a complete primary Contact Role; the error names exactly which details are missing. A bypass permission exists for admin-approved cases.
- **Bad Debtor account** — deals at ≥50% probability on an account flagged Bad Debtor by Finance are blocked; contact invoicing@lbresearch.com, or close the opportunity lost if the deal cannot proceed.
- **Close Date in the past** — open opportunities (except Cancellations) cannot be saved with a close date before today.
- **Currency restrictions** — Hong Kong entity sales cannot be in EUR.
- **Agency deals** — "Purchased Via = Agency" requires an End User account; "Purchased Via = Direct" requires it blank.
- **Sanctioned countries** — opportunities on accounts in sanctioned countries cannot be created or edited; contact the Salesforce team for compliance cases.
- **Renewal quotes** — on renewal quotes, a renewal uplift below 7.5% or removing auto-renewal requires `Renewal Term Justification` / `Special Terms` on the quote before saving.
