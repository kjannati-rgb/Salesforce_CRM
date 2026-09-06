# REV-57 — Jira drafts (for review; not yet posted)

> Draft only. On your go I'll (a) update the REV-57 description, (b) add the test-evidence comment, (c) create the 3 fast-follow tickets linked to REV-57.

---

## A) REV-57 — updated Description

**Summary:** Rebuild Pardot Form Completion (PFC) automation to handle Free Newsfeed Subscriber registrations and cross-link related enquiries — replacing the legacy single-purpose flow with a config-driven, source-agnostic engine.

**Problem.** Newsfeed sign-ups had no Salesforce handling (one hand-made prototype existed). The legacy `Create_Pardot_Form_from_Task` flow hard-coded record-type IDs and subject logic, and there was no way to see that the same person had engaged across multiple products. A related flow hard-coded production Campaign IDs (sandbox-breaking, prod-fragile), and lead conversion left PFCs stranded on the Lead.

**Solution (delivered).**
- **Unified orchestrator** (`Pardot_Create_PFC_Orchestrator`, Task-triggered) replaces the legacy flow and handles all four sources via the `PFC_Task_Mapping__mdt` CMDT: `NF - ` → Newsfeed, `PFC:` → Form Completion, `Lead scoring MQL` → Scored Leads, `EVT` → Events. New sources = a CMDT row, not a flow edit. Record types resolved by DeveloperName (no hard-coded IDs).
- **Newsfeed records** get Source = Newsfeed, Product Brand = Lexology, a readable Name (`[Person] | Lexology Newsfeed Subscriber - [Month Year] - MQL`), and the subscriber added to the **"Lexology – Free Newsfeed Subscribers"** campaign as **Registered**. Identity is taken from the Task WhoId, never parsed from the subject (hyphenated-name safe).
- **Cross-linking** (`PFC_Check_And_Link`, shared): if an open PFC exists for the same person + same brand-grain product, the new record links to it (`Related Form Completion` + "Linked Form Completions" related list). Symmetric (newsfeed↔inbound, both directions); skips closed records and unbranded/"Other".
- **Lead-conversion relink** (`PFC_Relink_Lead_to_Contact_on_Conversion`): on conversion, related PFCs move Lead → Contact automatically (fixes the "Contact doesn't show until you move the stage" bug).
- **Campaign resolution hardened**: `On_Pardot_Form_Creation` now resolves Campaign by name via `PFC_Campaign_Mapping__mdt` (no hard-coded Campaign IDs; sandbox-safe).
- **Non-functional:** bulk-safe (200/transaction tested), every DML fails open to `Flow_Log__c`, all tunables in CMDT.
- **UX (Phase 3):** Path on Sales Stage for every record type, new fields + Linked Form Completions on the Lightning page, tailored Newsfeed compact layout, "Newsfeed – Open" / "My Newsfeed" list views.

**Decisions:** record type kept as `Newsfeed_Subscribers` (rename dropped — cosmetic, zero references); assignment unchanged (Clay/ROE — `Clay_Routed__c = false`); campaign membership applies to inbound mapped forms too.

**Deployed to production 2026-06-10** (41 metadata components + atomic flow swap; inbound smoke-tested; 0 faults). Remaining: manual page/compact-layout activation + permission-set assignment; Pardot `NF - ` task build (marketing).

### Acceptance Criteria
1. A Pardot Task with subject starting `NF - ` creates a Newsfeed PFC: RT Newsfeed Subscribers, Source = Newsfeed, Product Brand = Lexology, Name `[Person] | Lexology Newsfeed Subscriber - [Month Year] - MQL`, person linked from WhoId; nothing parsed from the subject. ✅
2. If an **open** PFC (New/Working/Nurturing) exists for the **same person + same brand**, the new PFC links to it (both directions). Closed, different-brand, and "Other"/unbranded do **not** link. ✅
3. Existing `PFC:`/`Lead scoring MQL`/`EVT` creation is unchanged field-for-field, now via the orchestrator; legacy flow retired. ✅
4. On Lead conversion, related PFCs move Lead → Contact automatically (no stage-move). ✅
5. Newsfeed subscribers are added to the "Lexology – Free Newsfeed Subscribers" campaign as **Registered**, deduped. ✅
6. Bulk-safe (200 NF tasks in one transaction, no limit errors); every DML logs faults to `Flow_Log__c` and never blocks the record. ✅
7. New sources/brands/campaigns are configurable via CMDT with no hard-coded IDs. ✅

---

## B) REV-57 — Test-evidence comment

**Built & tested in KJDEV, then deployed to production (2026-06-10).**

Phase 4 — 10/10 scenarios PASS:
1. NF, no existing PFC → Newsfeed PFC, source/brand stamped, no link ✅
2. NF on Contact w/ open inbound, same brand → created **and** linked ✅
3. Inbound on person w/ open newsfeed → created **and** linked (reverse) ✅
4. Existing PFC Converted/Disqualified → new PFC, no link ✅
5. Open PFC, different brand → no link ✅
6. Hyphenated/apostrophe name ("Anna-Marie O'Brien") → correct, no subject parsing ✅
7. Bulk 200 NF tasks in one transaction → all created, no limits ✅
8. Inbound regression vs flow-1 baseline → field-for-field identical ✅
9. Non-matching prefix → no PFC ✅
10. DML fault injection → logged to Flow_Log__c, no silent loss ✅

Additional verified: conversion relink (Lead→Contact on convert); newsfeed naming + campaign membership (Registered); legacy-brand symmetry; all 4 source types route correctly.

**Production cutover:** 41 components deployed; atomic flow activation/deactivation; **inbound smoke test in prod PASS** (orchestrator created Form Completion PFC, parsed Form Name, Lead linked, then cleaned up); 0 `Flow_Log__c` faults. Rollback path retained (prior flow versions backed up).

---

## C) Fast-follow tickets (to create, linked to REV-57)

### Ticket 1 — PFC cross-link: email fallback for person matching
**Type:** Story · **Priority:** Medium · **Links:** relates to REV-57
**Description:** Cross-link matching currently keys on the literal `Lead__c`/`Contact__c`. Add `Email__c` as a fallback so identity survives lead↔contact duplication and edge cases the conversion-relink doesn't cover. Guard against over-matching on shared/free-mail domains (org has `Free_Mail_Domain__mdt`) — e.g. skip email-match when the domain is a known free-mail domain.
**AC:** Two PFCs for the same human with different Lead/Contact links but the same non-free-mail email cross-link; free-mail emails do not trigger spurious links.

### Ticket 2 — PFC cross-link: Apex unit tests / CI coverage
**Type:** Tech-debt · **Priority:** Medium · **Links:** relates to REV-57
**Description:** Cross-link + orchestrator logic is Flow-based (org convention) with no automated tests; regression rests on the manual Phase-4 plan. Add an invocable-Apex implementation (or Apex tests around the flows via a test harness) covering the 10 Phase-4 scenarios, so future changes are protected in CI.
**AC:** Automated tests cover create/link/no-link/closed/bulk/fault paths; run green in CI.

### Ticket 3 — PFC null record-type backfill (legacy data) [D4]
**Type:** Data job · **Priority:** Low · **Links:** relates to REV-57
**Description:** ~47k legacy PFCs (≈77%) have a null record type. Re-type them to `Form_Completion` (or correct per analysis) so reporting and the new list views/paths behave consistently. Out of REV-57 scope by design; run as a batched data job with validation (respect VRs, no automation storms — split into batches).
**AC:** All targeted legacy PFCs have a valid record type; no VR/automation failures; spot-check sample.

### (Also note, not tickets)
- **Pardot config:** build the `NF - ` completion-action/Task (marketing) — go-live dependency.
- **Manual prod steps:** compact-layout assignment, Lightning-page activation to Newsfeed RT, permission-set assignment.
- **Async path:** decide whether to add the legacy +1-min/batch-50 scheduled path for month-end surge (monitor first).
