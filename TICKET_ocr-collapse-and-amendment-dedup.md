# Ticket: OCR role-collapse (latent) + amendment duplicate-OCR creation (live)

**Reporter:** Kamyar Jannati — Head Data and CRM
**Date:** 2026-06-27
**Component:** Salesforce CPQ — OpportunityContactRole automation (PROD `00D6g0000081IOg`)
**Related:** OCR renewal fix (Phase 1/2, deployed 2026-06-27); ADR-001; discovery §3c
**Origin:** Spun out of the renewal-fix work while answering "do a contact's 3 distinct roles propagate onto the renewal?"

---

## Summary

Two distinct findings came out of investigating same-contact multi-role OpportunityContactRole (OCR) behaviour:

- **Finding A (latent, low):** Bulk/sequential **Apex inserts** of several OCRs for the *same contact* (one primary) **collapse them all to `Decision Maker / primary`**, and can trigger a recursion cascade that hits the SOQL governor limit (`Too many SOQL queries: 101`). This does **not** occur through live CPQ automation — only the direct Apex/data-load path.
- **Finding B (live, medium):** `Add_Contact_Roles_on_Amendments` copies a source opp's contact roles onto the amendment opp **with no de-duplication**, creating **exact duplicate OCRs** (incl. duplicate primary `Decision Maker`).

---

## Finding A — OCR role-collapse when adding a role to the opp's PRIMARY contact — ✅ RESOLVED 2026-06-27

### Resolution
**Root cause:** flow `Opportunity_Contact_Role_Create` (active **v6**) **unconditionally** rewrote any `IsPrimary=true` OCR's `Role` to `Decision Maker` (`myRule_3 → myRule_3_A1`, no guard). Since all of a primary contact's OCR rows carry `IsPrimary=true`, any added role was overwritten. (An abandoned **v7** had added a guard lookup but keyed it on `IsPrimary=true`, which misses the existing DM due to primary-flag timing — so it was never activated.) Confirmed via FINEST flow trace: `myRule_3_A1` set `Role=Decision Maker` on the added row.

**Fix (deployed PROD `Opportunity_Contact_Role_Create` v8, active 2026-06-27):** the guard lookup now keys on `OpportunityId + ContactId + Role='Decision Maker' + Id != $Record.Id` — i.e. skip the rewrite if this contact already has a Decision Maker on the opp; otherwise still normalise (intent preserved). Tested in FULLUAT (bug case: added Invoice Recipient preserved; intent case: lone primary Business User → normalised to Decision Maker). **Verified live** on `006Px00000Rmkx3IAB`: re-added Invoice Recipient now persists. **Rollback:** reactivate v6.

### Original severity / priority (now resolved)
**CONFIRMED LIVE — Medium/High (silent data loss).** Reproduced in the **production UI** on 2026-06-27: on opp `006Px00000Rmkx3IAB` (Primary Contact = Kamyar Jannati), manually adding Kamyar as **Invoice Recipient** was auto-rewritten to **Decision Maker / IsPrimary=true** (new OCR `00KPx00000WsAxdMAF`, created 14:54:40), producing a second Decision Maker row alongside the original (10 Jun). The Phase-2 guard logged it as a tolerated duplicate (14:54:42) and the nightly reconciler will remove the duplicate — but the **Invoice Recipient role is silently lost**. (Earlier "latent / Apex-only" assessment was WRONG.)

Key qualifier: affects roles added to the opportunity's **primary contact** (all of whose OCR rows carry `IsPrimary=true`). **Non-primary** contacts retain distinct roles (e.g. amendment opp `006Px00000Osj8pIAB`: a non-primary contact keeps `Decision Maker + Economic Decision Maker`).

### Reproduction (FULLUAT, 2026-06-27)
1. Create an Opportunity, and a Contact "Kam".
2. Insert (bulk **or** sequential) OCRs for Kam: `Decision Maker` (IsPrimary=true) + `Invoice Recipient` + `Economic Buyer`.
3. **Actual:** all three rows become `Decision Maker / IsPrimary=true`; the `Invoice Recipient` and `Economic Buyer` roles are lost. Sequential insert additionally hit `Too many SOQL queries: 101`.
4. **Expected:** three distinct preserved roles.

### What it is NOT
- **Not** caused by the renewal fix (guard / Phase 1 / reconciler) — they only touch exact `[Opp, Contact, Role]` duplicates.
- **Not** the `Opportunity_Contact_Role_Create` normaliser — the collapse still occurs with `Application_Settings__c.Disable_Process_Builders__c = true` (normaliser disabled).
- Mechanism appears to be a platform/managed behaviour of the OCR object on the direct-insert path (a primary contact's role rows being normalised), compounded by recursive automation re-entrancy.

### Nuance — why it can look inconsistent
- The rewrite hits the opp's **primary contact** only. Non-primary contacts keep distinct roles, so amendment opp `006Px00000Osj8pIAB` (non-primary contacts) and some historical records look "fine."
- Some historical records with a primary contact holding distinct non-DM roles exist (e.g. renewal `006Px00000QFmzrIAD`) — likely created before this behaviour, via CPQ clone, or a bypassed path. The exact conditions under which the rewrite does vs. doesn't fire are not yet fully characterised.

### Root cause — NOT yet definitively pinned
- **Not** the renewal fix (guard / Phase 1 / reconciler touch only exact `[Opp, Contact, Role]` duplicates).
- The `Opportunity_Contact_Role_Create` normaliser is the obvious suspect (it sets `Role='Decision Maker'` on primary OCRs), **but** the collapse still reproduced in an Apex isolation test with that flow disabled (`Disable_Process_Builders__c=true`) — so a managed-package/platform behaviour tied to the primary-contact designation may also/instead be involved. **Needs a flow+managed-trigger trace of a single live transaction to confirm the actor.**

### Recommendation
- **Pin the actor** (instrumented trace of the live add) before designing a fix.
- Then fix so that adding a non-DM role to a primary contact **preserves the role** (and either keeps a single Decision Maker or honours the entered role).
- Interim user guidance: adding extra roles to the **primary** contact will currently be overwritten to Decision Maker — add the non-DM role to the contact while they are not the primary, or expect to re-apply after.

---

## Finding B — `Add_Contact_Roles_on_Amendments` creates duplicate OCRs (live)

### Severity / priority
**Medium.** Actively creating duplicate OCRs in production. Partially mitigated (the new `OpportunityContactRoleReconciler` nightly batch deletes exact duplicates), but the flow should stop creating them at source.

### Detail
- Flow `Add_Contact_Roles_on_Amendments` (active) triggers on Amendment quote create, reads OCRs from `SBQQ__Opportunity2__r.Cancelled_Opportunity__c`, and creates each onto the amendment opp **with no check for an existing matching `[Opp, Contact, Role]`**.
- **Evidence (PROD):** amendment opp `006Px00000Osj8pIAB` contains `Technical Buyer ×2` (one contact) and `Decision Maker / IsPrimary=true ×2` (one contact) — exact duplicates.
- The duplicate primary `Decision Maker` is the same collision class that was silently failing renewals; on amendments it persists as a duplicate.

### Recommendation
- Make the amendment flow **idempotent**, mirroring the renewal-flow Phase 1 fix: before each create, Get an existing `[Opp, Contact, Role]` and skip if present.
- This is the amendment-path equivalent of ADR-001 Phase 1, and folds into ADR Phase 3 (single Apex OCR writer) as the durable end state.

---

## Suggested labels / linking
`salesforce`, `cpq`, `opportunitycontactrole`, `data-quality`. Link to the OCR renewal fix (Confluence: "CPQ Renewal Silent Failures — Root Cause & Fix") and ADR-001.
