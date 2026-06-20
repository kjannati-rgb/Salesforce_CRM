# Handshake SDR Notification — Deployment Runbook

_Author: Claude Code · Built/verified in KJDEV 2026-06-19 · Target: LBR_PROD_

## 1. What this delivers
Adds the Opportunity Team **Sales Development Representative** (TeamMemberRole = `Sales Development Representative`) **+ that user's manager** as recipients of the New-Business **Sales Handshake** emails (Lex Pro NB, Benefitting Group, Content Subs), on both lifecycle paths (NB-create + renewal/contract-out).

**Key architecture note:** the handshake emails are NOT sent by `Opp_Error_Saleshandshake` (that flow is a validation gate). They are sent by the **`Customer_Journey`** flow via three email alerts on the `Customer_Journey__c` workflow. This change leaves those alerts and templates **untouched** and adds a *separate* branded send to the SDR + manager.

## 2. Components in the change set
| Component | Type | New/Changed |
|---|---|---|
| `HandshakeSDRNotifier` | ApexClass | new |
| `HandshakeSDRNotifierTest` | ApexClass | new (2/2 pass) |
| `Send_Handshake_SDR_Notification` | Flow (autolaunched subflow) | new |
| `Customer_Journey` | Flow | changed — 5 subflow calls inserted after each handshake alert |

Untouched on purpose: the 3 Classic templates, the 3 Customer_Journey__c email alerts, `Opp_Error_Saleshandshake`.

## 3. ⚠️ CRITICAL pre-req — Email Deliverability
The SDR notification renders the Classic template via Apex and sends it as a **single email** (Salesforce blocks templated email with a record context to internal *User* recipients, so an alert can't be used).

- **Single email requires Deliverability "Access to Send Email" = _All email_** (Setup → Email → Deliverability).
- If the org is **"System email only"**, the SDR send is silently blocked (returns a failed result, absorbed by `allOrNone=false`); the existing business *alerts* keep working because they are system email.
- **KJDEV and FULLUAT are both "System email only"** → live delivery cannot be tested there without flipping the setting.
- **Confirm PROD = "All email" before deploying.** (Very likely already, since CPQ emails quotes to customers as single email — but verify.)

## 4. Pre-deploy checks (target org) — all confirmed present in PROD
- Templates active: `NB_Sales_handshake_Lex_Pro`, `NB_BG_Sales_handshake_Lex_Pro`, `NB_Sales_handshake_CS`
- Org-Wide Email Address `customersuccess@lbresearch.com`
- `Flow_log_v3` active (used for fault logging)
- `Customer_Journey` flow present (the deployed file is the PROD version + 5 inserts)

## 5. Deploy
```
sf project deploy start \
  -m "ApexClass:HandshakeSDRNotifier" \
  -m "ApexClass:HandshakeSDRNotifierTest" \
  -m "Flow:Send_Handshake_SDR_Notification" \
  -m "Flow:Customer_Journey" \
  -o LBR_PROD -l RunSpecifiedTests -t HandshakeSDRNotifierTest
```
Deploy all four together (the main flow references the subflow, which references the Apex class).

## 6. ⚠️ Post-deploy — ACTIVATE (PROD deploys flows as Draft)
LBR_PROD has "deploy flows as active" OFF. After deploy the flows land **inactive**; the old `Customer_Journey` version keeps running, so **the SDR notify will not fire until you activate**:
1. Activate **`Send_Handshake_SDR_Notification`** (the deployed version).
2. Activate the **new `Customer_Journey`** version.

(Setup → Flows → open each → Activate; or deploy a `FlowDefinition` with the new `activeVersionNumber`.)

## 7. Smoke test (post-activation)
On a real or test New-Business opportunity that has an SDR on the Opportunity Team:
- Drive it through the handshake (Closed Won path) so `Customer_Journey` creates the Sales Handshake and sends.
- ✅ SDR + manager receive the branded handshake email (from `customersuccess@lbresearch.com`).
- ✅ Existing business recipients still receive theirs (unchanged).
- ✅ No `Flow_Log__c` row with Flow_Name = `Send_Handshake_SDR_Notification` (a row there = a send fault to investigate).
- Edge checks: opp with no SDR → no SDR email, business email unaffected; inactive SDR/manager → excluded.

## 8. Rollback (business email never at risk)
- Re-activate the **prior `Customer_Journey`** version → SDR notify stops immediately; business alerts unaffected (never changed).
- Optionally deactivate `Send_Handshake_SDR_Notification`.
- Apex/templates/alerts need no rollback (Apex is inert if uncalled; templates/alerts were never modified).

## 9. Open decision (not blocking)
Built with **Apex** to honor "identical branded content" (verified: `renderStoredEmailTemplate` reproduces the template). If Apex is undesirable, the fallback is a **flow-only plain-text notification** (subject + link to the opp) — smaller, no Apex, but not the full branded body.

## 10. Verified in KJDEV (component level)
Recipient resolution (SDR + manager; inactive filtered; 0-SDR skips cleanly; >1 SDR all included), Classic-template rendering against the CJ record, send-shape, fault-safety (failures logged via `Flow_log_v3`, never break the parent), Apex tests 2/2.
**Not yet verified:** actual email delivery + full main-flow runtime trigger — both blocked by sandbox deliverability ("System email only"). Recommend a controlled prod smoke (Section 7) as the live gate.
