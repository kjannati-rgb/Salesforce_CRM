# PROD Deployment Runbook — OCR Renewal Fix (Phase 1 + Phase 2)

**Change:** Stop CPQ renewals silently failing on duplicate OpportunityContactRole (OCR) collisions.
**Owner:** Kamyar Jannati — Head Data and CRM
**Target org:** Law Business Research PROD (`00D6g0000081IOg`)
**Prepared:** 2026-06-27 · Status: **✅ DEPLOYED TO PROD 2026-06-27**

> **GO-LIVE LOG (2026-06-27):** Phase 1 + Phase 2 deployed to PROD (4/4 components, 3/3 tests, 0 errors). Flows activated via FlowDefinition: **`Opportunity_Contact_Role_Check_for_Duplicate` v9 Active** (non-blocking decoupled guard), **`Opportunity_Renewal_New_Records` v10 Active** (Phase 1 idempotency). Reconciler scheduled: **"OCR Reconciler Daily"** (0 0 2 \* \* ?), first run 2026-06-28 01:00 UTC. **Rollback point: guard→v7, renewal→v9.** Pending follow-ups: telemetry dashboard (needs PROD `runningUser`), Phase 1 renewal-click UAT confirmation, monitor first reconciler run + renewal throughput.
**Evidence:** `ocr-renewal-discovery.md`, `ocr-architecture-ADR.md` / `ADR-001_OCR_Write_Architecture.docx`

> Discovery and all builds to date are in KJDEV; PROD has only had a **validate-only** run (nothing saved). This runbook is the real go-live. Do **not** execute without sign-off and a green FULLUAT functional test.

---

## 0. Pre-requisites / sign-offs

- [ ] Change approved by Kam (RevOps/Data owner).
- [x] **FULLUAT Phase 2 functional test GREEN (2026-06-27)** — see §6 evidence. Guard tolerance + reconciler proven on real data. **Still outstanding: Phase 1 manual CPQ-renewal UAT** (§6 step 4) — the renewal flow was intentionally not pushed to FULLUAT (its renewal flow is v10, ahead of PROD v9; avoided regressing it).
- [ ] Deploy window agreed (low renewal-forecast activity; avoid month-end CPQ batch runs).
- [ ] Confirm `Application_Settings__c` switches exist in PROD (verified 2026-06-27): `Disable_Autolaunch_Lightning_Flow__c`, `Disable_Process_Builders__c`.
- [ ] Note current active versions for rollback: capture `FlowDefinition.ActiveVersion.VersionNumber` for `Opportunity_Renewal_New_Records` and `Opportunity_Contact_Role_Check_for_Duplicate` **before** deploy.

```bash
sf data query -o PROD -t -q "SELECT DeveloperName, ActiveVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName IN ('Opportunity_Renewal_New_Records','Opportunity_Contact_Role_Check_for_Duplicate')"
```

---

## 1. Package contents

| Component | Type | Purpose | Notes |
|---|---|---|---|
| `Opportunity_Renewal_New_Records` | Flow | **Phase 1** — idempotency check before creating the Decision Maker primary OCR | KJDEV flow = PROD flow + exactly the 3 Phase-1 elements (verified minimal diff) |
| `Opportunity_Contact_Role_Check_for_Duplicate` | Flow | **Phase 2** — reconcile-not-reject: logs the duplicate, no longer rolls back the renewal | **PROD-decoupled variant**: writes `Flow_Log__c` directly (no `Platform_Fault_Logger` subflow, which is a KJDEV-only Centellic pilot) |
| `OpportunityContactRoleReconciler` | ApexClass | **Phase 2** — async batch/schedulable that removes surplus `[Opp, Contact, Role]` rows | keep-rule: primary > oldest > lowest Id |
| `OpportunityContactRoleReconcilerTest` | ApexClass | Test (98% cov, 3/3) | |

Telemetry (deploy separately, §5): report folder **OCR & Renewal Health** + 4 reports + dashboard.

Source of truth for the package: scratch project `prodpkg/force-app/main/default` (validated against PROD 2026-06-27, checkOnly 4/4, 3/3 tests).

---

## 2. Deploy order & commands

> **PROD deploys flows as Draft** (the "deploy flows as active" org setting is OFF). The deploy creates **new inactive flow versions**; behaviour does **not** change until activation in §3.

1. **Final validate-only** (re-confirm against current PROD):
```bash
sf project deploy start -o PROD --dry-run -d prodpkg/force-app/main/default \
  -l RunSpecifiedTests -t OpportunityContactRoleReconcilerTest
```
2. **Deploy** (quick-deploy the validated run if available, else run for real):
```bash
sf project deploy start -o PROD -d prodpkg/force-app/main/default \
  -l RunSpecifiedTests -t OpportunityContactRoleReconcilerTest
```
Expected: 4/4 components, Apex test passes. Flows land as **Draft**.

---

## 3. Activate the flows (REQUIRED — the deploy alone is inert)

Both flows must be activated together so the renewal idempotency (Phase 1) and the non-blocking guard (Phase 2) take effect as a pair. Activate via Setup → Flows (activate the newly deployed version) or by deploying a `FlowDefinition` with the new `activeVersionNumber`.

- [ ] Activate the new `Opportunity_Contact_Role_Check_for_Duplicate` version (guard now non-blocking).
- [ ] Activate the new `Opportunity_Renewal_New_Records` version (renewal now idempotent).

Confirm:
```bash
sf data query -o PROD -t -q "SELECT DeveloperName, ActiveVersion.VersionNumber, ActiveVersion.Status FROM FlowDefinition WHERE DeveloperName IN ('Opportunity_Renewal_New_Records','Opportunity_Contact_Role_Check_for_Duplicate')"
```

---

## 4. Schedule the reconciler

Run once to verify, then schedule daily (off-peak):
```apex
// one immediate pass
Database.executeBatch(new OpportunityContactRoleReconciler(), 200);
// daily at 02:00
System.schedule('OCR Reconciler Daily', '0 0 2 * * ?', new OpportunityContactRoleReconciler());
```
Optionally bound scope to recent activity: `new OpportunityContactRoleReconciler('LastModifiedDate = LAST_N_DAYS:7')`.

---

## 5. Telemetry (reports + dashboard)

The 4 reports are portable as-is. The **dashboard `runningUser` must be changed** from the KJDEV user to a PROD user (a service/admin user with broad visibility) before deploy, e.g. `kamyar.jannati@lbresearch.com`. Then deploy the `reports/` and `dashboards/` folders. Dashboard components read `Flow_Log__c` (guard tolerations, reconciler runs, `RenewalOpportunityHandler2` errors) + Opportunity (renewal throughput).

---

## 6. FULLUAT functional test (do this BEFORE PROD)

The PROD validate-only proves compile + unit tests, **not** runtime. In FULLUAT (has data):
1. Deploy the same `prodpkg` + activate the flows.
2. **Guard tolerance:** on an existing opp, insert a second OCR with the same `[Opportunity, Contact, Role]` as an existing one. Confirm it **saves** (no "duplicate contact role" error) and a `Flow_Log__c` row is written (`Flow_Name__c = 'Opportunity_Contact_Role_Check_for_Duplicate'`).
3. **Reconciler:** run the batch; confirm the surplus row is deleted and one row per group remains; confirm a reconciler `Flow_Log__c` summary row.
4. **Renewal idempotency (Phase 1):** trigger a CPQ renewal forecast on a contract whose source opp has a primary Decision Maker OCR; confirm the renewal opp **is created** (previously rolled back) and has no duplicate Decision Maker OCR.
5. Clean up any test records created.

**Evidence — Phase 2 run on FULLUAT 2026-06-27 (real data):**
- Deployed guard (decoupled, non-blocking) + reconciler + test; guard activated as **v9 Active** (FULLUAT deploys flows as active, unlike PROD).
- **Guard tolerance:** inserted a duplicate `[006Px00000MR1hiIAD, contact, Decision Maker]` OCR → `tolerated=true`, no error, row committed (2→3), and **1 guard `Flow_Log__c` written**. (The prior v7 guard would have thrown "duplicate contact role" and rolled back.)
- **Reconciler:** ran scoped to that opp → job Completed, 0 errors; opp collapsed **3 → 1** OCR; summary log: *"Reconcile complete: deleted 2 duplicate OpportunityContactRole row(s) across 1 duplicate group(s)."* Test row auto-cleaned; a real pre-existing dup on that opp was also corrected.
- **FULLUAT left state:** non-blocking guard active + reconciler deployed (no schedule). Revert by re-activating the prior guard version if baseline is needed.
- **Not yet covered:** Phase 1 renewal idempotency at runtime (needs a CPQ renewal-forecast click — step 4).

---

## 7. Post-deploy validation (PROD)

- [ ] Spot-check that renewal opps are generating (compare daily counts vs the prior baseline; watch the **Renewal Opportunities Created** report).
- [ ] **Renewal Engine Errors** report (`RenewalOpportunityHandler2`) trending down.
- [ ] **OCR Duplicates Tolerated** report shows the guard logging (not blocking).
- [ ] Reconciler **OCR Reconciler Runs** shows deletions on its first scheduled pass.
- [ ] No spike in unrelated OCR errors.

---

## 8. One-time historical cleanup (optional, after stabilisation)

Existing duplicate OCRs created before this change can be swept by the reconciler. If doing a bulk **insert-based** backfill instead, remember the **dual kill switch**: disable **both** `Disable_Autolaunch_Lightning_Flow__c` **and** `Disable_Process_Builders__c` (the latter gates `Opportunity_Contact_Role_Create`, which force-rewrites primary OCR roles to "Decision Maker"). The async reconciler itself is unaffected (it only deletes; no OCR automation fires on delete).

---

## 9. Rollback

- **Flows:** re-activate the previously-active versions captured in §0 (Setup → Flows → Activate prior version, or deploy `FlowDefinition` with the old `activeVersionNumber`). Instant; no data migration.
- **Reconciler:** unschedule (`System.abortJob` on the CronTrigger). Deleted duplicate rows are not auto-restored, but they were redundant `[Opp, Contact, Role]` copies by definition.
- **Apex classes** can remain deployed (inert if unscheduled and the flow no longer references them) or be removed in a follow-up.

---

## 10. Known divergence to converge later

The PROD guard writes `Flow_Log__c` directly; the KJDEV guard uses the shared `Platform_Fault_Logger` (Centellic Stabilise pilot). When that pilot is promoted to PROD, re-point the PROD guard's `Log_Duplicate` step to the shared subflow so both orgs converge. This is the interim deliverable of ADR-001 Phase 2; Phase 3 (single Apex OCR writer + retire the CPQ native clone) supersedes it.
