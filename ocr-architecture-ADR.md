# ADR-001 — OpportunityContactRole write architecture for CPQ renewals

| | |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-06-27 |
| **Owner** | Kamyar Jannati — Head Data and CRM |
| **Decision scope** | How OpportunityContactRole (OCR) records are created, deduplicated, and validated across CPQ renewal, amendment, and conversion paths |
| **Evidence** | `ocr-renewal-discovery.md` (PROD, read-only discovery) |

---

## Context

CPQ renewal opportunities silently fail to generate for a subset of contracts. Root cause is architectural, not a single bug:

- **Multiple uncoordinated OCR writers** run in one renewal transaction — CPQ's native `SBQQ__DefaultRenewalContactRoles__c` clone (true on **41,508 of 41,511** Contracts), the `Opportunity_Renewal_New_Records` flow (creates a hard-coded `Decision Maker`/primary OCR with no existence check), and `Add_Contact_Roles_on_Amendments` (copies all roles, no dedupe). None is aware of the others; none is idempotent.
- **A hard-blocking guard** (`Opportunity_Contact_Role_Check_for_Duplicate`, after-save Flow) throws a Custom Error on a duplicate `[Opp, Contact, Role]` and **rolls back the entire renewal transaction** — Opp + Quote + Quote Lines — so the renewal is never committed and no error reaches anyone.
- **Identity is keyed on `ContactId`, not the person** — the same human as two Contact records is never deduped, corrupting renewal forecasting and ChurnZero segmentation downstream.

This pattern does not scale: it produces silent revenue-pipeline loss and recurring fire drills. The specific Decision-Maker collision is one instance of the class.

## Decision

Adopt a **single OCR orchestration layer in Apex** as the sole writer of OCRs on renewal/amendment/conversion paths, with the following properties:

1. **One writer.** All OCR create/clone logic moves into one `with sharing` service (`OpportunityContactRoleService`). CPQ's native renewal clone is **disabled** once the service is proven (see migration); the scatter of after-save flows stops writing OCRs independently.
2. **Idempotent by design.** The service writes a role only when `[Opp, Contact, Role]` does not already exist. Duplicates become impossible to create rather than created-then-rejected. Bulk-safe, set-based, unit-tested.
3. **Guard reconciles, does not reject.** The duplicate guard is converted from a hard Custom Error to a **non-blocking reconciliation** (drop/merge the extra row, log it, let the business transaction commit). A CRM-hygiene rule must never be able to roll back a revenue object. A hard block is retained only for genuinely invalid states.
4. **Person-level identity.** Dedupe on a contact match key, not `ContactId` — shared primitive with the Lead Conversion / match-key roadmap.
5. **Observability on success.** Renewal-forecast runs emit success / fail / skipped counts; a failed renewal raises a *visible* signal (dashboard/Slack), not a silent null `Flow_Log__c`.
6. **Business knobs stay in CMDT.** Which roles, thresholds, and toggles live in Custom Metadata (extending the `Contact_Role_Check_Setting__mdt` pattern) so RevOps tunes behavior without a deploy.

### Explicit CPQ-config decision

`SBQQ__DefaultRenewalContactRoles__c = true` on 41,508/3 Contracts is a package default nobody chose. We **decide on purpose**: the custom service owns OCR writes; the native CPQ clone is turned **off for renewals** once the service is live. This removes the dual-writer collision at its source. (Reversible: re-enabling the field restores native behavior.)

## Why Apex, not more flows

The renewal engine is already heavy Apex (`RenewalOpportunityHandler2`); the failure came precisely from flows racing each other at bulk. Bulk, ordering-sensitive, transaction-critical record orchestration belongs in one tested service, not per-record after-save flows that each fire their own SOQL. Flows remain the right tool for RevOps-ownable field logic — the business rules stay in CMDT.

## Consequences

**Positive:** duplicates structurally impossible; renewals never roll back on contact-role hygiene; single debuggable code path; person-level dedupe cleans forecast/ChurnZero data; renewal failures become visible.

**Costs / risks:** custom code assumes work CPQ did for free — the service **must be live and reliable before** the native clone is disabled (sequencing is load-bearing). One-time bulk field update on ~41.5k Contracts. Migration touches revenue-critical automation — phase it, never big-bang.

## Migration phases

1. **Now — unblock (days, reversible):** add the idempotency check to `Opportunity_Renewal_New_Records`; stops the active silent failures.
2. **Stabilize:** convert the guard to reconcile-and-log; instrument renewal success/failure telemetry. Incidents become visible and non-fatal.
3. **Consolidate:** stand up `OpportunityContactRoleService`; migrate renewal + amendment paths onto it; retire obsolete/duplicate flows (incl. the v9 draft guard); **then** disable the CPQ native clone for renewals.
4. **Strategic (compounds):** person-level match-key dedupe, shared with Lead Conversion — fixes OCR dupes and the data you own.

Steps 1–2 stop the pain in days; 3–4 deliver the best-in-class, scale-safe end state.

## One-time cleanup

Dedupe existing multi-role OCRs (created by the no-dedupe flows) **under the org kill switch** `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c`, so future logic doesn't carry collisions forward.
