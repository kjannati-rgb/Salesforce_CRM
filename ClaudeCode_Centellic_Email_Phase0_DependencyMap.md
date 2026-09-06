# Centellic Email Upgrade — Phase 0 Dependency Map (source-resolved portion)

**Date:** 20 Jun 2026 · **Org:** LBR (UK) / Centellic · **Scope of this pass:** what is resolvable from
the metadata already in this repo (`force-app/main/default`), read-only. No org access, no deploys.
**Companion:** `Centellic_dependency-map.csv` (machine-readable) · runbook `Centellic_Email_Template_Upgrade_Runbook.md` §3 Phase 0.

> This is the *partial* dependency map — the slice automation that is version-controlled here. It is
> enough to (a) prove the firing model and (b) catch disposition conflicts before anything is touched.
> The rest of the estate (renewals, Pardot, eSign, CPQ Advanced Approvals, approval processes) fires
> from config records / managed packages **not in source** and needs the org retrieve to finish the map
> (see §4 Coverage gaps).

## What's in source to map against

| Type | Count in repo | Carries template refs? |
|---|---|---|
| Flows | 246 | Yes — 25 `emailAlert` action calls |
| Workflows | 2 (`Opportunity`, `Customer_Journey__c`) | Yes — 25 `<alerts>` with `<template>` |
| Apex classes | 54 | One dynamic renderer (`HandshakeSDRNotifier`), template name passed at runtime |
| Email templates | 3 (the Sales-Handshake set) | n/a |
| Approval processes | **0** | — (this is why the SA approval set can't be confirmed here) |

**Firing model confirmed:** templates fire via **Workflow Email Alerts that are invoked from Flows**
(`<actionType>emailAlert</actionType>`), *not* from Flow "Send Email" actions and *not* from active
workflow rules (the rules in `Opportunity.workflow` are field-update only). This matches the runbook's
note that `TimesUsed` is null on flow-fired templates.

## 1. Conflicts the inventory got wrong (must fix before Phase 6 retire/quarantine)

Every row below is **actively fired by an in-source flow** but carries a disposition that would
deactivate or sideline it. Retiring/quarantining these breaks live sends.

| Template (DeveloperName) | Inventory disposition | Reality (fired-by) | Correct disposition |
|---|---|---|---|
| **`TestBadDebtor`** (CPQ AA Opp) | **Retire** ("test artefact") | `Opportunity.BadDebtorClosedLostEmailAlert` → 1 flow | **KEEP / Upgrade** — load-bearing despite the name |
| `WWL_Closed_Won_Opportunity_1719699423239` | **Quarantine** | 3 alerts (`WWL_closed_won`, `WWL_Annual_Report`, `WWL_Annual_Licence`) → 3 flow calls | **KEEP / Upgrade** |
| `LexPro_Opp_Closed_Won_1709065892738` | **Quarantine** | `Opportunity.LexPro_Closed_Won_Alert` → 1 flow | **KEEP / Upgrade** |
| `Closed_Won_Email_Alert_to_admin_1723627895026` | **Quarantine** | `Opportunity.Closed_Won_Deal` → 1 flow | **KEEP** (internal ops alert) |
| `Closed_Lost_reasons_Opportunity` | **Review (legacy)** | `PRO_/CS_Closed_lost_reasons` → 4 flow calls | **KEEP / Upgrade** |
| `Data_Team_Enrich_Account` | **Review** | `Opportunity.Data_Team_Enrich_Account` → 3 flow calls | **KEEP** (internal data-team alert) |
| `NB_Sales_handshake_Lex_Pro` / `_CS` / `_BG` | **Review** | Customer-Journey handshake alerts → 7 flow calls total | **REFERENCE/KEEP** — already v3-aligned, in source, the gold set |

**Headline:** `TestBadDebtor`'s name is a trap. It reads like a test artefact and the inventory
retires it, but it is the live Bad-Debtor closed-lost notification. This is the single highest-risk
item in the retire list and exactly what dependency-first exists to catch.

## 2. Confirmed in-scope, disposition already correct

| Template | Disposition | Fired-by | Note |
|---|---|---|---|
| `Opportunity_Credit_Card` (CPQ AA Opp) | Upgrade (T2) | `Opportunity.opportunity_Credit_Card` → 1 flow | ✓ |
| `Requesting_for_Direct_Debit` (CPQ AA Opp) | Upgrade (T2) | `Opportunity.Opportunity_Direct_Debit_Card` → 1 flow | ✓ |

## 3. Cannot confirm from source — flag "verify in-org" (do NOT retire blind)

These alert **definitions** exist in `Opportunity.workflow` but **no in-source flow invokes them** —
they are almost certainly fired by **Approval Processes** (the SA legacy approval set), which are not in
this repo. The inventory's `Retire (verify refs)` disposition is therefore *correct in spirit* — the
"verify refs" step is: inspect the Opportunity approval-process email-alert steps in-org.

| Template | Disposition | Alert definition (unwired in source) |
|---|---|---|
| `Opportunity_Approved_Message` (SA Opp) | Retire (verify refs) | `Approval_email_notification` |
| `Opportunity_Auto_Closed_Lost` (SA Opp) | Retire (verify refs) | `Opportunity_Auto_Closed_Lost` |
| `Opportunity_Recall_Message` (SA Opp) | Retire (verify refs) | `Opportunity_Recall_email_notification` |
| `Opportunity_Rejected_Message` (SA Opp) | Retire (verify refs) | `Rejection_/Opportunity_Rejection_email_notification` |
| `CS_Contact_Notification` (unfiled) | Review (legacy) | `Opportunity.CS_Contact_Notification` |

Also unwired-in-source (dormant alert definitions, template kept but no flow call): `CS_NB_Handshake`,
`PRO_NB_Handshake`, `Sales_handshake`, `Lex_Pro_NB_Handshake2`, `Content_Subs_NB_Handshake2` — all
point at the handshake templates, so they're duplicate/legacy alert wiring, not extra templates.

## 4. Coverage gaps — what the org retrieve must still resolve

The source map covers **Opportunity + Customer_Journey email alerts only**. Still unmapped (needs
`sf project retrieve` + in-org config queries):

1. **Renewal canon (22 Classic "Mail Trap" templates, all T1 Upgrade).** Fired by the `Ast_*`
   renewal-batch package (only its *test* classes are in source; the senders are managed/in-org). The
   batches select templates by **`Email_Template_Id__c` on a config/CMDT record** — so live-status is
   config-driven and **invisible to source**. This is the biggest unmapped customer-facing block.
2. **CPQ Advanced Approvals** (`sbaa__ApprovalRule__c` / approval conditions) — the `AA Quote:` VF
   template wiring is config records, query in-org.
3. **SA approval processes** — see §3; not in repo.
4. **Pardot (5), eSign/Adobe Sign (8)** — agreement-status + Account Engagement automation, not in repo.
5. **Quote + User alerts** — 3 in-source flow calls reference alerts whose templates aren't in source:
   `SBQQ__Quote__c.Finance_Team_Notification_for_Quote_Direct_Debit_Payment`, `User.New_User_SF_login`,
   `User.New_user_notification`.

## 5. Recommended adjustments to the inventory before any Phase 6 action

- Reclassify the 8 §1 templates from Retire/Quarantine/Review → **Keep/Upgrade** (mark them
  `live: flow-fired`).
- Keep the SA-approval set at `Retire (verify refs)` but make the verify step explicit: **read the
  Opportunity approval-process alert steps in-org first**.
- Treat the renewal canon as **un-auditable from source** — its dependency proof requires querying the
  `Ast_*` batch config in-org. Until then, do not mark any renewal template for retire.
- The handshake set (`NB_*`) is already the v3 reference — move it from `Review` to the gold/keep set.

---

*Generated read-only from repo metadata on 20 Jun 2026. Org-side completion of the map (renewals, CPQ
AA, approval processes, Pardot, eSign) is the next Phase 0 step and requires the `sf project retrieve`
in §3 of the runbook.*
