# REV-57 — D5 Resolution: Newsfeed trigger mechanism

**Date:** 2026-06-10 · **Method:** production (`LBR_PROD`) read-only data analysis (Pardot/MCAE admin UI not accessible from here).
**Question:** Does Pardot fire an `NF - ` **Task** (→ Task-triggered flow), or does B2BMA write the **PFC record** directly?

## RESOLVED — Option A (Pardot-created `NF - ` Task)

**Confirmed by Kam 2026-06-10:** newsfeed will be a **new Task created by Pardot**, with the `NF - ` subject, *specifically so the source can be distinguished*. It is **not configured in Pardot yet** but is planned for go-live. So all four sources (NF / PFC: / Lead scoring MQL / EVT) are **Task-driven** — vindicating the runbook's "thin Task orchestrator" vision and making the subject-prefix CMDT (`PFC_Task_Mapping__mdt`) we built in Phase 1 directly applicable.

The data below remains the record of *why* this had to be a deliberate config decision (nothing was live to observe — the one record is a hand-made prototype).

## Evidence

| # | Query (prod) | Result | What it proves |
|---|---|---|---|
| 1 | `Task WHERE Subject LIKE 'NF -%'` | **0** | The `NF - ` subject convention is **not in use anywhere yet**. No NF-Task path exists today. |
| 2 | All `Newsfeed_Subscribers`-RT PFCs | **1** (the prototype `a5EPx00000W7743MAB`), CreatedBy B2BMA, **LastModifiedBy Ken Fitzgerald** | Single record, connector-created then hand-edited. Not a running pipeline. |
| 3 | Flow (1) record-type formula (Phase 0) | yields only Form_Completion / Scored_Leads / Events_Sponsorship | The **existing Task→flow chain literally cannot produce a Newsfeed-RT PFC** → the prototype did *not* come from it. |
| 4 | Inbound: `PFC:` Tasks vs Form_Completion PFCs (30d) | **960 = 960**, 1:1, all CreatedBy B2BMA | Inbound is unambiguously **Task-driven**; "CreatedBy B2BMA" is NOT a direct-write signal (it owns the Task path too). |
| 5 | Prototype `Salesforce_Pardot_Form_Completions_ID__c` | = its own Id; `Prospect_ID__c` = the Contact Id; templated Name | Connector write-back + manual finishing — a prototype, not pipeline output. |
| 6 | Prototype's Contact's other Tasks | `EVT:` / `ES:` (B2BMA, same day), no `NF -` | The contact came in via an Event click, not a newsfeed Task. |

## What this rules out
- ❌ "Pardot already fires `NF - ` Tasks" — zero exist.
- ❌ "The current flow already has a Newsfeed branch" (runbook's assumption) — Phase 0 §1 + finding #3 both disprove it.
- ❌ "CreatedBy = B2BMA ⇒ direct write" — false; B2BMA owns the inbound Task path too (finding #4).

## Recommended SF architecture (given Option A)

**Unified Task-triggered orchestrator that replaces flow (1)**, CMDT-driven, with a **shared autolaunched Check-&-Link subflow** used by every source — the rebuild's whole point.

- **Entry:** Task after-save (create), Subject `StartsWith` any active `PFC_Task_Mapping__mdt.Subject_Prefix__c`.
- **Resolve:** match prefix (by `Match_Priority__c`) → CMDT row → RT DeveloperName, Source, Default_Brand, parse rules. Resolve WhoId → `Lead__c` / `Contact__c`.
- **Create:** PFC with RT (resolved by DeveloperName, no hardcoded Id), `PFC_Source__c`, `Product_Brand__c` (from Default_Brand or derived), Form_Name per parse rules, plus the legacy 4-field set flow (1) stamps. Newsfeed: `Parse_Form_Name=false`, brand `Lexology`.
- **Check & Link (shared subflow):** query open PFCs for same person + same brand (`Product_Brand__c = :b OR (Product_Brand__c = null AND Brand__c = :b)`) + Sales_Stage IN open set; if found, set `Related_Form_Completion__c` on the new record.
- **Assign:** per D2.
- **Cutover:** deactivate flow (1) only when the new orchestrator is live and Pardot's `NF - ` Task config is switched on.

> Note: an alternative was a PFC-record-create trigger (robust to a direct-write source). With Option A confirmed (all sources Task-driven), the Task orchestrator is the cleaner fit and the subject-prefix CMDT applies natively — so that hedge is dropped. Sequence the Check-&-Link step *after* Create, since the new record must exist before its `Related_Form_Completion__c` can be set.

## Still owed before go-live
- **Pardot config:** the `NF - ` completion-action / Task creation must actually be built in Pardot (D5 calls this out) and its exact subject string confirmed to match `NF - ` (D5-original).
- **D2:** newsfeed assignment (owner / sales rep) — currently defaulted to mirror inbound.
