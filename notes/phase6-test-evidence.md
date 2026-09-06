# Phase 6 — KJDEV Test Matrix Evidence

Run 2026-08-01 against KJDEV. All 5 rows pass. Deploy IDs and record Ids below are the evidence trail.

**Test-only substitution:** KJDEV has no record at the hardcoded `AccountId` (`0016g00001AQ7lXAAT` is a PROD-only Id — KJDEV was confirmed to have 0 matching rows). For T1–T5 the flow was temporarily deployed with `AccountId` pointed at KJDEV's own `Test` / Office account (`001Ae00000wb6y0IAA`), tested, then **reverted to the real `0016g00001AQ7lXAAT` value and redeployed** before this evidence was written up. The file in `force-app/` and everything below "Gate 2" reflects the canonical, prod-matching v4 — the substitution never left the flow in that state.

**License note:** KJDEV's `Salesforce` user-license pool was at 520/520 (exhausted) partway through this run — T1–T3 used it, T4 hit the cap. T4/T5 were created under the `Minimum Access - API Only Integrations` profile (`Salesforce Integration` license, headroom available) instead. Flow behavior is not license-dependent, so this doesn't affect result validity, but it's a preexisting KJDEV capacity issue worth knowing about for future test data work in this sandbox.

| # | Scenario | User Id | Result |
|---|---|---|---|
| T1 | Happy path | `005Ae00000KvxZNIAZ` | User persisted; Contact `003Ae00001BAuPrIAL` created with correct AccountId; no notification branch taken. **PASS** |
| T2 | **Blank first name** | `005Ae00000Kw5ztIAB` | User persisted (`FirstName` null, `LastName` "."); zero Contacts with matching email; `Blank_First_Name` decision branch taken. **PASS — acceptance test** |
| T3 | Duplicate email | `005Ae00000Kw64jIAB` | User persisted; Contact count for the shared email stayed at 1 (no second Contact); `Duplicate_Contact_Exists` branch taken. **PASS** |
| T4 | Unexpected VR failure | `005Ae00000Kw66LIAR` | Throwaway always-fail Contact VR (`CCFU_T4_Always_Fail`) deployed, User created, VR removed immediately after. User persisted; zero Contacts created; fault caught by `Create_Contact`'s `faultConnector`. **PASS — acceptance test** |
| T5 | Regression vs v3 | `005Ae00000Kw6G1IAJ` | Contact `003Ae00001BBSF3IAP` — `Department`/`Phone` pass through unchanged from v3's mapping, matches expected output exactly. **PASS** |

## Unplanned finding surfaced by testing

An earlier T5 attempt (`005Ae00000Kw6BBIAZ`, User only — no Contact, kept for reference) additionally populated `ManagerId`. That attempt produced **no Contact and no error visible to the CLI caller** — the User persisted but the Contact silently failed. Root-caused via anonymous Apex (`FIELD_INTEGRITY_EXCEPTION, Reports To ID: id value of incorrect type`): `Create_Contact`'s `ReportsToId` input assignment reads `$Record.ManagerId`, which is a **User** Id, but `Contact.ReportsToId` is a lookup to **Contact**. This mapping is unchanged from v3 (§8.5 — explicitly out of scope to touch) and is a **pre-existing v3 defect**, not something v4 introduced.

Implication: before v4, any Azure AD user provisioned **with a manager set** would have hit the same unhandled-fault rollback as the 01 Aug incident — a different root cause, same failure mode, and plausibly a much larger population of silent provisioning failures than the single FirstName case this runbook was written for. v4's fault handling (C1) caught it correctly and generically — this wasn't a scenario C1 was designed around, and it still worked, which is a good sign for C1's robustness beyond the anticipated failure mode.

**Left untouched per runbook scope.** Flagged for Kam as a separate decision, not folded into this change.

## Gate 2

All five rows pass with evidence. Proceeding is contingent on Kam's review of the `ReportsToId` finding above and explicit go-ahead for Phase 7.
