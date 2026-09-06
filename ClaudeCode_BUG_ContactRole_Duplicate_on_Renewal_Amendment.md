# BUG — "Duplicate contact role" blocks Quote/Contract saves on renewal & amendment

**Status:** Confirmed in PROD (LBR_PROD), 2026-06-17. Diagnosis only — no fix applied.
**Severity:** High — blocks a user-facing save (renewal/amendment quote generation) with a hard error.
**Reported instance:** Contract `00046249` (`800Px00000dZQhBIAW`) → error *"Error while saving Quote Records: This is an duplicate contact role, please use existing contact role."*

---

## Symptom
CPQ renewal/amendment quote generation fails and rolls back with:
> Error while saving Quote Records: This is an duplicate contact role, please use existing contact role

The inner message is the custom error thrown by the active flow **`Opportunity_Contact_Role_Check_for_Duplicate`** (v7, after-save on OpportunityContactRole).

## Root cause — a bug *class*, not one flow
Two **active** flows create OpportunityContactRole (OCR) records **with no "already exists" guard** (no upsert). They were authored when nothing enforced OCR uniqueness; the duplicate-check enforcement is **newer** than they are. Now, when they try to (re)create a role the opp already has, the dedup flow throws an exact-duplicate error **inside the enclosing Quote/Contract save transaction**, so the whole save rolls back.

**Duplicate definition (authoritative — `Opportunity_Contact_Role_Check_for_Duplicate` v7):** matches on `OpportunityId = $Record.OpportunityId AND ContactId = $Record.ContactId AND Role = $Record.Role AND Id != $Record.Id`. So it blocks an **exact** Opp+Contact+Role duplicate (different roles for the same contact are fine).

### Member 1 — `Opportunity_Renewal_New_Records` (Active) — direct cause of the reported instance
- Subflow of the `Opportunity` orchestrator; runs on the new **renewal** opp.
- `Create_Opportunity_Contact_Role` blind-creates: `ContactId ← recordId.Primary_Contact__c`, `IsPrimary = true`, `Role = "Decision Maker"` (hardcoded), `OpportunityId ← recordId.Id`.
- **No guard** — the flow's only `recordLookups` are for line items, not existing OCRs. If a "Decision Maker" OCR for that contact already exists on the renewal opp (e.g. CPQ already copied it, or a prior run), this creates a duplicate → dedup throws.
- The reported contract's quote `Q-175651` is `SBQQ__Type__c = Renewal`; its opp `006Tm00000FKa6jIAD` carries a **duplicate "Decision Maker"** (2 rows, one contact) — the fingerprint of this flow.

### Member 2 — `Add_Contact_Roles_on_Amendments` (Active) — same bug on the amendment path
- After-save on `SBQQ__Quote__c`, `Create`, `SBQQ__Type__c = Amendment`.
- `Get_Contact_Roles_from_Opp` reads **all** OCRs on `$Record.SBQQ__Opportunity2__r.Cancelled_Opportunity__c` (`getFirstRecordOnly=false`, no role/contact filter), then **loops and blind-creates** each on `$Record.SBQQ__Opportunity2__r.Id`.
- **No guard** — copies everything, including any pre-existing duplicates on the source. Collides with the dedup the same way.
- Does **not** fire on the reported (renewal) record, but is the identical defect on amendments. Blast radius: **1,419** amendment quotes in the org.

## Why it surfaces now
`Opportunity_Contact_Role_Check_for_Duplicate` enforcement post-dates the copy flows. Before it was active, duplicates simply accumulated — visible in the data (one contact holds the **same** role 14×; org-wide there are many exact-duplicate OCRs). Now the enforcement catches the copy flows mid-save and converts silent dup-creation into a hard save failure.

## Evidence
- Flow logic: `Opportunity_Renewal_New_Records` `Create_Opportunity_Contact_Role` (Role hardcoded "Decision Maker", no OCR existence lookup); `Add_Contact_Roles_on_Amendments` loop-create with no guard; `Opportunity_Contact_Role_Check_for_Duplicate` v7 match on Opp+Contact+Role.
- Data: opp `006Tm00000FKa6jIAD` has 2× "Decision Maker" for one contact; another opp has 14× "Event Logistical Contact" for one contact; 1,419 amendment quotes; OCR role list shows duplicate/typo values (`Invoice Recipient` vs `Contact Invoice Recipient`, `Decison Maker` typo, 636 null roles).

## Recommended fix (KJDEV-first, no prod change yet)
1. **Add an upsert guard to both flows.** Before each `Create`, look up an existing OCR by `OpportunityId + ContactId + Role`; if found, **skip the create** (route to the next iteration / continue), don't insert. Make the amendment loop bulk-safe (dedupe the source collection in-memory too).
2. **Keep the v7 dedup as the backstop** — the guards prevent the collision; the dedup stays for manual entry.
3. **Optional follow-ups (separate tickets):** (a) one-off cleanup of pre-existing duplicate OCRs; (b) rationalize the OCR Role picklist (merge variants/typos, handle nulls). These are not required to stop the save failures.

## Test plan (KJDEV)
- Renewal: renew a contract whose opp already has a primary "Decision Maker" → save succeeds, no second OCR created.
- Amendment: amend a contract whose cancelled opp shares roles with the amendment opp → save succeeds, no duplicates created.
- Regression: a brand-new renewal/amendment with no pre-existing roles → roles created exactly once.
- Manual dup (UI): adding the same Opp+Contact+Role by hand still blocked by v7.

## Safety / rollback
Both flows are gated by `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` (org kill-switch). Changes are additive (a guard); rollback = redeploy the prior flow version. Note `Opportunity_Renewal_New_Records` is a subflow of the heavy `Opportunity` orchestrator — validate in KJDEV against the full renewal cascade.

## Out of scope
The broader contact-consolidation initiative (one entry point per contact) — see `ClaudeCode_ContactConsolidation_Phase0_Diagnosis.md`. This bug must be fixed first because the consolidation's Quote→OCR write-back would hit the same collision.

---

## FIX STATUS — built & deployed to KJDEV + FULLUAT 2026-06-17 (NOT in prod)

**`Opportunity_Renewal_New_Records` (KJDEV v9 Active):** added an explicit guard before `Create_Opportunity_Contact_Role` — new lookup `Get_Existing_Primary_OCR` (OpportunityId = recordId.Id AND ContactId = recordId.Primary_Contact__c AND Role = 'Decision Maker') → new decision `Primary_OCR_Exists` (found → skip to `Check_for_lexology_pro_campaign`; not found → create). Plus a `faultConnector` on the create (→ skip) as a same-transaction-race safety net. Lookup faults fail-open to the original create (no new failure modes vs. today).

**`Add_Contact_Roles_on_Amendments` (KJDEV v4 Active):** added a `faultConnector` on the loop's `Create_New_Contact_Role` → back to `Loop_through_Contact_Roles`, so a duplicate (existing-target OR source-internal) is skipped gracefully instead of failing the whole quote save. Bulk-safe (no added SOQL).

**Prereq deployed:** `Opportunity.Previous_Annual_Contract_Value_Local__c` (Currency) — existed in prod, missing from KJDEV; the prod-active renewal flow references it.

**Validation (KJDEV):**
- *Bug mechanism (debug log):* inserting a 2nd identical `Decision Maker` OCR → `FIELD_CUSTOM_VALIDATION_EXCEPTION, "This is an duplicate contact role…"` (the exact prod error). Confirms the dedup is the thrower and the error is a catchable DmlException (so flow faultConnectors catch it).
- *Guard logic (deterministic):* the guard's lookup finds the pre-existing OCR → skip branch fires; no duplicate created; no error.
- *Wiring:* both flows activated (Salesforce validates all connectors on activation).
- *FULLUAT (full-data, CPQ sandbox — deployed renewal v10 / amendment v4 Active):* on the real reported opp `006Tm00000FKa6jIAD` (contract 00046249) the guard's lookup finds Ina's existing Decision Maker (skip fires), and a blind duplicate create still throws the exact `This is an duplicate contact role` error — i.e. the fixed flow's guard avoids the create the dedup would otherwise block. Savepoint/rollback; nothing persisted.
- *Limitation:* the renewal flow can't be faithfully driven headless outside the real CPQ renewal process (it ignores injected `Pardot_Form_Completion__c`; no flow-level trace). The canonical E2E is a human running Renew/Amend in the FULLUAT UI — see manual UAT script below.

## Manual UAT script (FULLUAT UI)
1. Open a Contract whose renewal/amendment Opportunity already has a primary `Decision Maker` Contact Role for its `Primary_Contact__c` (the reported one was contract `00046249`).
2. Click **Renew** (or **Amend**) and generate the quote.
3. **Expected (fixed):** the quote saves with no error and no new duplicate Contact Role. (Pre-fix this threw *"Error while saving Quote Records: This is an duplicate contact role…"*.)
4. Verify on the renewal/amendment Opportunity: Contact Roles have no exact `Contact + Role` duplicates introduced by the save.

**Not yet done:** prod deploy (awaiting review); one-off cleanup of pre-existing duplicate OCRs; OCR Role-picklist rationalization.
