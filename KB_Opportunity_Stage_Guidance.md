# Opportunity Stage Guidance — Definitions & Exit Criteria

**Audience:** Sales & Account Management (all motions: New Business, Renewals, Cancellations)
**Purpose:** What each stage *means*, what must be **true** to advance, and the **buyer-verifiable evidence** required — so the stage reflects reality and the forecast can be trusted.
**Pairs with:** [`KB_Opportunity_Stage_Movement.md`](KB_Opportunity_Stage_Movement.md), which covers the *mechanics* (which validation rule fires and how to clear the error). This document covers the *substance* (what's true about the deal). Use both: this one tells you when a deal has *earned* the next stage; the other tells you how to get past the system gate.

> **Golden rule:** a stage is a statement about **what the customer has done or agreed**, not about what the seller has done. "I sent a proposal" is seller activity. "The customer confirmed they're evaluating us against a deadline" is buyer-verifiable. Stages move on the second kind of evidence.

---

## Centellic context (from production data — what actually drives our deals)

- **We are a multi-brand publisher/intelligence business.** Top sellers by value: Law.com / Law.com International, Events, Specialist Platforms (GAR/GCR/IAM/WTR), Lexology PRO, Lexology Intelligence/Index, Expert Insight (Panoramic/In-Depth/GXRs), MBL Seminars, Docket Navigator, Performance Data. Guidance is one path per motion, not per product — but the product gates differ (Expert Insight needs products added before leaving Identify; Top ID/Group ID is ALM Subscriptions & Intelligence Services only).
- **New Business is rep-prospected.** The dominant lead source is *Self-Sourced – Sales* by a wide margin, then events, data leads, form completions, direct enquiry. An Identify opp is usually a prospect a rep is working — not an auto-created record.
- **We lose deals to budget, engagement and ROI — almost never to competitors.** Top loss reasons: Budget, Client engagement, **LBR engagement (our own)**, Buyer issues, No-fault cancellation, Lack of ROI. Competitor losses are tiny. So qualification and the path emphasise budget, two-way engagement, and demonstrated ROI — not competitive positioning.
- **The NB record type also carries expansion** — Repeat Business and Upsell to existing customers, not just new logos.

## The qualification standard (house standard — captured at Qualify)

We do not run full enterprise MEDDPICC on every £2k subscription. The house standard is a **5-point qualification (P-E-B-D-C)**, captured before a deal leaves **Qualify**. For Enterprise / Site-Licence / multi-product deals, expand to the full MEDDPICC mapping in the right-hand column.

| House standard (every deal) | What "true" looks like | MEDDPICC (Enterprise deals) |
|---|---|---|
| **P — Pain** | Customer has named a problem our product solves (not "might be interested") | Metrics + Identify Pain |
| **E — Economic buyer** | We know who controls the budget and they're aware of the deal | Economic buyer |
| **B — Budget** | Budget exists or a route to it is confirmed | Metrics |
| **D — Decision process & date** | We know how they decide and a target date | Decision criteria + process + Paper process |
| **C — Champion** | A named contact wants this to happen and will act internally | Champion (+ Competition) |

If you cannot evidence all five, the deal is **not** past Qualify — regardless of how much activity has happened.

---

## Stage-by-stage guidance

Probabilities and forecast categories below are the live configuration and are **empirically supported from Evaluate onward** (see "Why this changed"). Each stage lists: what it means · enter when · **to advance, this must be TRUE** (buyer-verifiable) · evidence required in Salesforce · the short in-app "Guidance for Success" copy.

---

### 1 · Identify — 10% · Forecast: Open (Pipeline)
- **What it means:** A potential opportunity exists. Most New Business is **self-sourced by Sales** (the dominant lead source), with some inbound from events, data leads, form completions and direct enquiry. *Unworked* until a contact engages.
- **Enter when:** The opportunity is created.
- **To advance (must be TRUE):** A real person at the account has **engaged** — replied, taken a call, or accepted a meeting — and there is a reason to believe a need exists. (Buyer action: they responded.)
- **Evidence in Salesforce:** Logged activity (call/email/meeting) with a named contact; Lead Source set.
- **In-app guidance:**
  > Identify = unworked. Advance to Qualify only when a real contact has engaged and there's a genuine need to explore. An auto-created record with no human response stays here. Don't skip Qualify — qualify the deal next.

---

### 2 · Qualify — 20% · Forecast: Open (Pipeline)  ⟵ **rewritten**
- **What it means:** The qualification gate. This is where we prove the deal is real against the **5-point house standard**. **Do not skip this stage** — an unqualified deal that looks advanced is the main cause of slipped forecasts.
- **Enter when:** A contact has engaged and we're actively working the deal.
- **To advance (must be TRUE):** All five qualification points are evidenced — **Pain, Economic buyer, Budget, Decision process & date, Champion** — and the customer has **agreed a concrete next step** (a scheduled evaluation, demo, or proposal review). (Buyer action: confirmed a problem we solve *and* committed to a next step.)
- **Evidence in Salesforce:** Qualification fields populated (the 5 points); a Primary Contact Role; a scheduled next activity; Amount reflecting a real expected value.
- **In-app guidance:**
  > Qualify = "is this real?" You may advance only when all five are true: **P**ain named, **E**conomic buyer known, **B**udget exists, **D**ecision process + date understood, **C**hampion engaged — and the customer has agreed a next step. If any are missing, stay here and close the gap or disqualify. Strong deals do **not** skip Qualify.

> **Why the emphasis:** historically ~70% of *winning* deals skipped this stage and deals parked here converted *below* Identify — because Qualify had no definition. With a real bar, Qualify becomes the stage that protects the rest of the funnel.

---

### 3 · Evaluate — 50% · Forecast: Best Case
- **What it means:** The customer is actively assessing us against their need (and usually against alternatives).
- **Enter when:** Qualification is complete and the customer is reviewing a solution/proposal.
- **To advance (must be TRUE):** The customer has **agreed the success criteria / scope** and a **proposal or quote has been shared and acknowledged**, with a mutual path to a decision. (Buyer action: agreed what "good" looks like and is reviewing commercials.)
- **Evidence in Salesforce:** Quote/proposal attached or linked; agreed close plan with a next date; products on the opportunity reflecting scope.
- **In-app guidance:**
  > Evaluate = the customer is actively assessing us. Advance only when success criteria are agreed and a proposal/quote is in their hands with a path to decision. **Set a mutual close date** — deals stall here more than anywhere else; if there's no agreed next date, it's not really at Evaluate.

> **Stall warning:** 40% of deals in Evaluate haven't moved in 90+ days. If you can't name the customer's next action and date, the deal is slipping — pull it back to Qualify or set a real next step.

---

### 4 · Negotiate — 75% · Forecast: Best Case
- **What it means:** The customer wants to proceed; we're agreeing terms, price, and paperwork.
- **Enter when:** The customer has signalled intent to buy, subject to commercials.
- **To advance (must be TRUE):** The customer has given a **verbal/written commitment to proceed** and we are finalising terms — they are moving to paper. (Buyer action: said yes, subject to terms.)
- **Evidence in Salesforce:** Approved/near-final quote; agreed price and payment terms; redlines or order process underway.
- **In-app guidance:**
  > Negotiate = "yes, subject to terms." Only deals where the customer has verbally committed and is agreeing commercials belong here. If you're still convincing them of value, that's Evaluate.

---

### 5 · Contract Out — 90% · Forecast: Most Likely
- **What it means:** The contract/order is with the customer for signature.
- **Enter when:** Terms are agreed and paperwork has gone out.
- **To advance (must be TRUE):** A contract/order has been **issued to the customer to sign** (genuinely out — not "about to send"). (Buyer action: they have the paper.)
- **Evidence in Salesforce:** **Contract Attached** is set *automatically* by the `Update_Opportunity_Contract_Attached_Field` before-save flow once a contract file (pdf/docx/msg/eml/jpg/png) **or** a CPQ/Adobe quote document (`SBQQ__QuoteDocument__c`, status Sent/Signed/Pending) is on the opportunity. It is **not** a manual tick — the rep's action is to *attach the contract / send the quote*.
- **In-app guidance:**
  > Contract Out = paperwork is with the customer to sign. Issue the contract (or send the CPQ quote document); the system sets **Contract Attached** automatically once it's on the opportunity. This stage is for deals out for signature, not deals you intend to send paperwork to.

---

### 6 · Closed Won – Pending Approval — 95% · Forecast: Commit
- **What it means:** The customer has **signed**; the deal is awaiting internal Finance approval. **It is not won yet** — this is still an open stage.
- **Enter when:** Signed contract is in hand.
- **To advance (must be TRUE):** **Signed contract attached** and all closing data complete; the record auto-submits to Finance approval. (Buyer action: signed.)
- **Evidence in Salesforce:** Signed contract on the opportunity (sets Contract Attached). The rest of the close gate is **validated automatically** — Ultimate Account, Lead Source, Contact Role, Sales Handshake, no open Success-Plan tasks, End User where applicable; a missing item blocks the save with the exact error (see the mechanics KB). **Top ID / Group ID applies to ALM Subscriptions & Intelligence Services only** — not Events or other motions.
- **In-app guidance:**
  > Pending Approval = customer signed, Finance approving. Make sure the **signed** contract is on the opportunity; the rest of the close checks run automatically and the save tells you if anything's missing. The deal flips to Closed Won only after Finance approves — you do not set Closed Won yourself.

> **Naming note:** this stage is labelled "Closed Won – Pending Approval" but the deal is **open** until approved. Treat "signed, awaiting Finance," not "won."

---

### 7 · Closed Won — 100% · Forecast: Closed
- **What it means:** Finance approved; revenue booked.
- **Set by:** The approval process, not the rep.
- **Capture:** Win-reason capture exists (`Won_Reason__c`) but is populated on only ~20% of wins, so it's treated as optional unless the team runs win analysis — not surfaced on the path.
- **In-app guidance:**
  > Closed Won is set by Finance approval once the Pending Approval stage is approved.

---

### 8 · Closed Lost — 0% · Forecast: Omitted
- **What it means:** The deal will not proceed.
- **To set (must be TRUE):** A **structured loss reason is recorded — for every team, no exceptions.** Capture Primary Reason + Sub-reason + a one-line Note. Most losses are Budget, Client/LBR engagement, Buyer issues, No-fault cancellation, or Lack of ROI — competitor losses are rare, so only tick one if you're sure.
- **Evidence in Salesforce:** `Closed_Lost_primary_reason__c` + sub-reason + Note populated.
- **In-app guidance:**
  > Closing Lost? Record the **Primary Reason, Sub-reason and a one-line Note** — always. "No reason given" is itself a reason; blank is not. This is how we fix what's losing us deals.

> **Config dependency:** today the loss-reason requirement is only *enforced* for three business groups (PI / MI / MBL); 94% of other teams' lost deals have no structured reason. Guidance asks everyone to comply, but to make it stick the validation must be extended to all teams (see "What guidance can't fix").

---

## Motion-specific notes

**New Business** — the default ladder above. Note the funnel is high-volume/low-conversion at the top: many Identify records are leads, not deals. Qualify is where you separate them.

**Renewals** — an existing customer; the conversation is *continuation*, not first-sale.
- **Enter at Evaluate, not Identify.** RevOps policy is that a known renewal starts at Evaluate (the relationship is already qualified). Don't leave renewals sitting in Identify/Qualify.
- **Buyer-verifiable evidence is different:** current usage/engagement, the existing contract, and the customer's stated intent to renew (or the renewal quote acknowledged).
- **Advance promptly:** a renewal in an early stage understates its true likelihood — renewals win ~50% and retain ~87% by value, far above the 10–20% the early stages imply.
- **Forecast Status is the renewal health field** (`Forecast_Status__c`, ~99% populated on renewals at every stage) — set it from Identify onward. It is surfaced on the renewals path at all open stages. (Not used on New Business, ~2–10%, so it is deliberately *not* on the NB path.) Renewal *risk group* and *contract expiry* are not captured as fields today — Forecast Status is the only health signal.

**Cancellations** — an internal churn-processing motion, not a sale.
- Stages used: **Cancellation – Pending Review (95%)** → **Closed Won – Cancellation (100%)**, both Omitted from forecast.
- "To advance," the cancellation must be **approved** (`Approved__c`). This isn't a buyer-persuasion flow; the "evidence" is internal authorisation and a recorded reason.

---

## Why this changed (grounded in the data)

- **Probabilities Evaluate→Pending are accurate and unchanged.** Empirical win rates for real (≥£5k) deals: Evaluate 46% (vs 50%), Negotiate 78% (vs 75%), Contract Out 93% (vs 90%), Pending 99% (vs 95%). The ladder is sound; it just lacked definitions.
- **Qualify was the broken stage.** It converted at ~19% — *below* Identify (~25%) — and ~70% of winners skipped it, because it had no bar. The rewrite makes it the qualification gate so the rest of the funnel means something.
- **Exit criteria are now buyer-verifiable.** Previously every gate was seller hygiene (fields, checkboxes, approvals). Each stage now states what the *customer* must have done.
- **Loss reason is asked of everyone.** Today only ~6% of non-PI lost deals carry a reason; the guidance closes that (enforcement change noted below).

---

## What guidance alone can't fix (config changes — prototype in KJDEV)

These need metadata changes, not just wording. Listed so the guidance isn't undermined by the configuration:

1. **Renewal probability curve.** Renewals run the new-business 10–20% defaults but win ~50%. Until renewal stages carry renewal-appropriate probabilities (or a renewal-specific forecast treatment), £140M+ of likely-renewing pipeline is mis-forecast as near-dead. *Biggest forecasting fix.*
2. **Extend loss-reason enforcement to all teams** (not just PI/MI/MBL). This is what turns the Closed Lost guidance above from a request into a guarantee.
3. **Fix the renewal stage-advance flow.** The scheduled flow that should move renewals to Evaluate writes a **dead "Evaluation" stage value** (the active stage is "Evaluate") — which is why renewals sit unadvanced. Repair before relying on the Renewals guidance.
4. **Build this guidance into a Sales Path** (per record type) so the "in-app guidance" copy above appears on the record, with the key fields surfaced per stage. Without a Path, this document is the reference but reps get no in-context prompt.

---

*Built from production stage configuration, validation rules, flows, and empirical Opportunity/OpportunityHistory analysis. Pairs with the mechanics KB for gate-clearing steps.*
