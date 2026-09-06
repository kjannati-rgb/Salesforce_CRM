# Spec — Align Cancellation opp contact roles with Amendments

**Author:** Kamyar Jannati — Head Data and CRM
**Date:** 2026-06-27 · Status: **Draft for review (no build yet)**
**Related:** `TICKET_ocr-collapse-and-amendment-dedup.md` (Finding B), ADR-001, OCR renewal fix (Confluence: "CPQ Renewal Silent Failures")

---

## 1. Objective

Make **Cancellation** opportunities carry the **same contact roles** as their source opportunity — exactly as **Amendment** opportunities already do — so the two opp types are aligned. **Decision: copy ALL roles** (mirroring amendment behaviour), not just the primary.

## 2. Current state (data-confirmed, PROD, 2026-06-27)

| | Amendment opps | Cancellation opps |
|---|---|---|
| Contact roles copied from source? | **Yes** | **No** |
| Mechanism | `Add_Contact_Roles_on_Amendments` flow | none |
| Evidence | 196 Amendment quotes / 180d | 160 Cancellation opps / 180d, **1** OCR total |

- `Add_Contact_Roles_on_Amendments` triggers on **`SBQQ__Quote__c` create where `SBQQ__Type__c = 'Amendment'`**, reads source OCRs from `$Record.SBQQ__Opportunity2__r.Cancelled_Opportunity__c`, loops, and creates one OCR per source role on the amendment opp.
- **There is no "Cancellation" CPQ quote type** (types in use: Quote, Renewal, Amendment, Re-Quote). So the amendment flow cannot simply be extended to cancellations — there is no cancellation quote to trigger on.
- **The hook exists on the opp:** all 160 cancellation opps have **`Cancelled_Opportunity__c`** populated → the source opportunity (where the roles live).

## 3. Design

Because cancellations have no quote, copy roles off the **Opportunity**, not a quote.

### 3.1 New flow — `Add_Contact_Roles_on_Cancellations`
- **Object / trigger:** `Opportunity`, record-triggered, **Create and Update**, *after-save*.
- **Entry conditions:** `Type = 'Cancellation'` **AND** `Cancelled_Opportunity__c` is not null. (Create-and-Update with idempotency covers the case where `Cancelled_Opportunity__c` is set at creation vs. a moment later.)
- **Kill switch:** honour `$Setup.Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` (same as the amendment flow) — first decision, exit if disabled.
- **Get source roles:** `OpportunityContactRole WHERE OpportunityId = {!$Record.Cancelled_Opportunity__c}`.
- **Idempotency (REQUIRED):** also Get existing OCRs on the cancellation opp; for each source role, **create only if** no `[OpportunityId = $Record.Id, ContactId, Role]` already exists. (Prevents duplicates on re-fire / re-run — the defect the amendment flow currently has.)
- **Create per source role**, mirroring the amendment flow's fields exactly:

| Field on new OCR | Value |
|---|---|
| `OpportunityId` | `$Record.Id` (the cancellation opp) |
| `ContactId` | source `ContactId` |
| `Role` | source `Role` |
| `IsPrimary` | source `IsPrimary` |
| `CurrencyIsoCode` | source `CurrencyIsoCode` |
| `Original_Account__c` | source `Original_Account__c` |

### 3.2 Fix the amendment flow (`Add_Contact_Roles_on_Amendments`) — Finding B
Apply the **same idempotency check** to the existing amendment flow so it stops creating exact-duplicate OCRs. Both paths then use one correct pattern and genuinely "match."

### 3.3 Strategic option (recommended end-state)
Rather than maintain three divergent role-copy flows (renewal, amendment, cancellation), fold all three into a **single Apex OCR-copy service** (ADR-001 Phase 3). Aligning cancellations is the natural moment to converge. **Decision needed:** ship a dedicated cancellation flow now (fast, low-risk), or invest in the shared service now (more work, durable). Recommendation: dedicated idempotent flow now + amendment fix; converge to the service under Phase 3.

## 4. Behavioural notes / why this is safe

- **No CPQ impact.** Cancellations have no CPQ quote clone, so nothing competes with this flow (unlike renewals, where CPQ's `DefaultRenewalContactRoles` clone runs).
- **Primary handling is already correct.** Copying roles (incl. `IsPrimary`) means the source's primary contact becomes the cancellation opp's primary contact. The `Opportunity_Contact_Role_Create` v8 fix preserves multiple distinct roles for that contact; the "two Primary ticks" that results is **standard Salesforce** (per-contact primary) and expected — **do not** add a single-primary validation (it would also break CPQ renewals).
- **Guard interaction.** The non-blocking duplicate guard (v9/v10) tolerates and logs; the flow's own idempotency means it shouldn't fire in the first place.
- **Bulk-safe.** Standard record-triggered flow bulk handling; one Get for source roles + one Get for existing roles, set-based create.

## 5. Open questions / decisions
1. **Scope of "all roles"** — confirmed: copy all (incl. non-primary). ✔
2. **Dedicated flow vs. shared Apex service** — see §3.3 (recommend flow now).
3. **Timing** — confirm `Cancelled_Opportunity__c` is populated at/within the create transaction (all 160 current ones have it; Create-and-Update + idempotency makes this robust regardless).
4. **Cancellations with no source roles** — no-op (nothing to copy); acceptable.

## 6. Test plan (FULLUAT — has data)
1. Cancellation opp whose source has **multiple contacts incl. one primary with multiple roles** → all roles copied, primary preserved, no duplicates.
2. **Re-fire** (update the cancellation opp again) → no new/duplicate OCRs (idempotency).
3. Source with **no roles** → no-op, no error.
4. Amendment flow regression: amendment opp → roles copied, **no duplicates** (the dedup fix).
5. Confirm `Disable_Autolaunch_Lightning_Flow__c = true` suppresses both flows.

## 7. Deployment plan
- Build in **KJDEV** → deploy/test in **FULLUAT** → validate-only against **PROD** → deploy.
- **PROD deploys flows as Draft** → activate the new flow + the amended flow via `FlowDefinition` after deploy.
- **Rollback:** deactivate the new cancellation flow; reactivate the prior amendment flow version. Instant, no data migration. (Already-copied roles can be left or cleaned by the reconciler.)

## 8. Out of scope
- Back-filling historical cancellation opps with missing roles (separate one-off, optional — could be a batch off `Cancelled_Opportunity__c`).
- The single-primary / two-ticks behaviour (standard Salesforce; explicitly not changing).
