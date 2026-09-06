# Moving an Opportunity Through (and Back Through) Its Stages

**Audience:** Sales & Account Management
**Applies to:** Opportunity records in Salesforce
**What this covers:** What each stage gate actually checks, the exact error you'll see, and the exact step that clears it — so you can self-serve before raising a case.

> The stage path is: **Identify → Qualify → Evaluate → Negotiate → Contract Out → Closed Won – Pending Approval → Closed Won**. **Closed Lost** is the lost path. Note that **"Closed Won – Pending Approval" is still an open stage** — the deal is *not* won until Finance approves it and it flips to **Closed Won**.

---

## Quick answers

| You're trying to… | Can you do it yourself? | What stops you / what to do |
|---|---|---|
| Move a stage **backward** while the opp is still open (e.g. Negotiate → Qualify) | **Yes** | No rule blocks backward movement between open stages. Just change the Stage and save. (Other field rules below may still fire.) |
| Move backward **out of Closed Won** or **Closed Lost** | **No** | The record is locked once it was Closed Won/Closed Lost. A Salesforce admin must do it. |
| Set the stage directly to **Closed Won** | **No** | You must use **Closed Won – Pending Approval** and let it go through Finance approval. |
| Advance past **Contract Out** | Only after the signed contract is attached | Tick/attach the contract (see below). |
| Move to **Closed Won – Pending Approval** | Yes, once all closing requirements are met | See the closing checklist below. |

---

## a. Can I move an Opportunity's Stage *backward* myself?

**Yes — as long as the opportunity is still open.** There is no validation rule or flow that blocks moving the Stage to an earlier open stage (for example Negotiate back to Evaluate, or Contract Out back to Negotiate). Change the Stage picklist and save.

**The two exceptions — when it *is* blocked:**

1. **The opportunity is already Closed Won.**
   - **Error:** *"This Opportunity is Closed Won and can no longer be edited. Please contact your Salesforce administrator if a change is required."*
   - **Why:** Once an opp has been Closed Won, the record is locked to everyone except admins/Finance.
   - **To clear:** Raise a case — an admin must reopen it.

2. **The opportunity is already Closed Lost.**
   - **Error:** *"This Opportunity is Closed Lost and can no longer be edited. Please contact your Salesforce administrator if a change is required."*
   - **To clear:** Raise a case — an admin must reopen it.

> A separate lock exists for opportunities flagged as **deleted** (*"This Opportunity is locked because it has been marked as deleted…"*). Those also need an admin.

**Important nuance about "backward":** Moving backward isn't blocked, but **lowering the win probability or changing the stage can re-trigger field checks** that were satisfied at a higher stage (for example the Contact Role completeness check below stays active at 50%+ probability). If a save is rejected after you move backward, read the error — it's almost always one of the field rules below, not the backward move itself.

---

## b. What does **Contract Out** require before the opp can advance?

**A signed/attached contract.** This is the single gate on the Contract Out stage.

- **Rule:** `Contract_Not_Attached_at_Contract_Out`
- **Fires when:** Stage = **Contract Out** **and** the **Contract Attached** checkbox is *not* ticked.
- **Error:** *"Please send out the contract to sign or attach the necessary document before proceeding to close."*
- **To clear:** Send the contract for signature / attach the document, then tick **Contract Attached** on the opportunity.

> **The "Sales Handshake" is a separate, later gate — not a Contract Out gate.** Despite the name, the Sales Handshake (Customer Journey) check does **not** fire at Contract Out. It fires when you move to **Closed Won – Pending Approval**, and only for certain product types — see the closing checklist below.

---

## c. What blocks moving to **Closed Won – Pending Approval** / **Closed Won**?

### You cannot set Closed Won directly
- **Rules:** `Opportunity_cannot_be_Closed_Won_by_User` and `Opportunity_must_be_submitted_for_approv`
- **Error:** *"Sales Rep cannot move the Opportunity to Closed Won. Please 'Submit for Approval'."* / *"You cannot close an Opportunity directly. Please 'Submit for Approval'."*
- **What to do:** Move the stage to **Closed Won – Pending Approval** instead. The system submits it to Finance approval automatically; it becomes **Closed Won** only after approval.

### Closing checklist — everything that can block the move to *Closed Won – Pending Approval*

Work through these; each one names the exact error and the exact fix.

1. **Products on the opportunity** *(for Expert Insight price books — Lexology Panoramic, Lexology In-Depth, GXRs)*
   - **Rule:** `Add_products_to_the_opportunity`
   - **Error:** *"To move opportunity stage from Identify, please add products."*
   - **Fix:** Add at least one product line.

2. **Complete primary Contact Role** *(applies once win probability is 50% or higher)*
   - **Enforced by:** the *Check Completeness of Contact Roles* flow (this replaced the old "Contact Role Complete" validation rule).
   - **Error (dynamic — it lists exactly what's missing):** *"This Opportunity needs a complete primary Contact Role before it can be saved at this win probability. Please provide: …"*
   - **Fix:** Add a **Primary** Contact Role whose Contact has: **First Name, Email, Job Title, Mailing Street, Mailing City**; and whose **Account** has **Billing Street, Billing City, Billing Country**. The error text tells you which specific fields are still blank.
   - **Note:** CPQ amendment/renewal opportunities (amended contracts) are exempt, and users with the **Bypass Contact Role Check** permission are exempt.

3. **Signed contract attached** *(at Closed Won – Pending Approval)*
   - **Rule:** `Contract_Not_attached_at_closed_won_pend`
   - **Error:** *"Please attach signed contract before pushing opp for approval."*
   - **Fix:** Tick **Contract Attached**.

4. **Top ID** *(ALM Intelligence/Subscription products only — not ALM Events)*
   - **Enforced by:** the *Opportunity Before Save* flow.
   - **Error:** *"Please add Top ID before pushing opp to 'Closed Won - Pending Approval'."*
   - **Fix:** Populate the **Top ID** field.

5. **Sales Handshake (Customer Journey) complete** *(Lexology PRO, Content Subscriptions, or Benefitting-Group products)*
   - **Enforced by:** the *Opp Error Saleshandshake* flow, which reads the Customer Journey record.
   - **Error:** *"Please complete '<field name>' in the Sales Handshake before progressing the opportunity"* (the exact field varies — e.g. Goal licenses, Other licence contacts, Set up instructions, Features discussed, Work areas & Jurisdictions, Primary use case/challenge, Risk/Expansion, etc.).
   - **Fix:** Open the linked **Customer Journey / Sales Handshake** record and fill in the field named in the error.

6. **Ultimate Account on the Account**
   - **Rule:** `Ultimate_Account_Mandatory_for_closing` (fires on the move to **Closed Won**)
   - **Error:** *"Please make sure the Account has an associated Ultimate Account before proceeding."*
   - **Fix:** Set the **Ultimate Account** on the related Account.

7. **Lead Source** *(New Business record type, high probability)*
   - **Rule:** `Lead_Source_Mandatory_for_Closing`
   - **Error:** *"Please enter a valid Lead Source."*
   - **Fix:** Populate **Lead Source**.

8. **No open "Complete Success Plan" tasks**
   - **Rule:** `Opp_With_Open_Complete_Success_Plan_Task`
   - **Error:** *"You have open Complete Success Plan tasks on this opportunity. Please complete them before closing the opportunity."*
   - **Fix:** Complete the outstanding Success Plan task(s).

9. **End User (if Purchased Via = Agency)**
   - **Rule:** `End_user_mandatory` (and the mirror `End_User_Must_be_Blank` if Purchased Via = Direct)
   - **Error:** *"Please enter an End User"* / *"If the 'Purchased Via' is Direct, the end user must be left blank."*
   - **Fix:** Set or clear the **End User** to match **Purchased Via**.

**Other rules that can fire around closing** (less common, listed so you recognise them):
- **Close Date in the past** → *"Close Date must be in the future."* Set a future Close Date. *(The system auto-stamps today's date when an opp goes Closed Lost.)*
- **Bad debtor account** → *"This Account… has been flagged by Finance as having a Debt…"* Contact **invoicing@lbresearch.com**.
- **Sanctioned country** → *"Opportunities cannot be created or edited for Accounts based in sanctioned countries…"* Raise a case.
- **Hong Kong + EUR** → *"Sales made from Hong Kong cannot be processed in EUR currency…"* Change the currency.
- **Repeat Business without a Previous Opportunity** → *"Opportunities classified as 'Repeat Business'… must have a specified previous opportunity."* Set **Previous Opportunity**.
- **Closed Lost without reason/note** → *"Please complete both Closed Lost Primary Reason and Note…"* (and sub-reason / competitor name where applicable). Fill them in.
- **Cancellation not approved** → *"This Cancellation must be approved before it can be closed. Please submit it for approval."*

### Quote state
The data layer notes that quote approvals run through approval paths (Big Deal, Payment Terms & Payment Type, Specific Countries, Auto-Approve). **The specific quote-approval rules are CPQ Advanced Approvals configuration and are not visible in this org's stored metadata**, so this article can't state the exact quote conditions. Practically: if your **Primary Quote** is not in an **Approved** state, expect the close to be blocked or the approval to stall. (A rule requiring an approved primary quote, `Primary_Approved_Quote_Required`, exists but is currently **inactive**.)

---

## d. Who approves "Closed Won – Pending Approval"?

- When you move an opp to **Closed Won – Pending Approval** (or **Cancellation – Pending Review**), it is **automatically submitted for approval** — you do not click "Submit for Approval" yourself in normal flow.
- Approval is handled by **Finance** via the org's Finance approval processes (e.g. *Finance Approval Process* and its ALM / Events / Cancellation variants).
- **Who the individual approver is** (the named user or queue at each step) is defined inside those approval-process configurations, which are **not part of this metadata set** — so this article can't name the specific approver. If you need to know who your approval is sitting with, check the **Approval History** related list on the opportunity, or raise a case.
- While an opp is pending approval the record is typically **locked for editing** until the approval is approved or recalled/rejected.

---

## When to still raise a case — and what to include

Raise a support case when:
- The opp is **already Closed Won or Closed Lost** and needs reopening or backward movement (only an admin can do this).
- The opp is **stuck in approval** — submitted but not moving (check **Approval History** first; if it's sitting with someone unavailable, say so).
- You hit an error whose **fix you've already done** and it still blocks you (possible stale data or a system issue).
- The blocker is a **compliance** item (sanctioned country, bad-debtor flag) you can't resolve yourself.
- You believe a **quote approval** is the blocker and the quote already looks approved.

**To get it resolved on the first reply, include:**
1. **Opportunity ID** (the 15/18-character Id, or a direct link to the record).
2. **What you tried** — the exact Stage change (from → to) or field edit.
3. **The exact error message** — copy/paste the full text (screenshots help).
4. **The business reason / urgency** — e.g. "needs to close today for month-end," "customer signed, contract attached."
5. For approval issues: what the **Approval History** shows (submitted date, current approver/step).

---

## Notes & limitations of this article

- Built from the org's stored metadata (validation rules + record-triggered flows + the Contact-Role custom-metadata settings) as of the date below.
- **Stage ↔ win-probability mapping** (which stage equals 50%, 90%, etc.) is set on the Opportunity Stage picklist, which isn't in this metadata set — so "50% probability" is stated by probability, not by stage name. Confirm the mapping in Setup if exact stage boundaries matter.
- **Approval-process internals** (approvers, step routing) and **CPQ quote-approval rules** are not in this metadata set and are flagged as such above.
- Several rules are **globally switchable** by admins (a "Disable Validation Rules" setting and a "Run Validation Rule" setting) and many **exempt** System Administrator / Finance-Ops profiles — so an admin may not see the same block you do.
