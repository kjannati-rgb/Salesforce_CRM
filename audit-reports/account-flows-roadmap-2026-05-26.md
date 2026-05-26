# Account Flows — Refactoring Roadmap

**Org:** KJDEV sandbox · **Date:** 2026-05-26 · **Companion to:** `account-flows-audit-2026-05-26.md`

Effort key: **S** ≤ ½ day · **M** ~1–2 days · **L** ~3–5 days. All work targets the KJDEV sandbox first; nothing here has been executed.

---

## Phase 1 — Quick wins (low risk, high value, < 1 day)

| # | Action | Effort | Risk | Test scenarios |
|---|---|---|---|---|
| 1.1 | **Delete the dead legacy Process Builder** `Account_Object_Create_Edit` (inactive, API 49, superseded by `_1`). | S | Very low (already inactive) | Confirm it is inactive in Setup; deploy deletion; smoke-test an Account create/edit. |
| 1.2 | **Deactivate/remove `Sample_Flow_to_Debug`** (active, orphaned, 2 DML incl. Account). **BUSINESS CONTEXT NEEDED** first. | S | Low (no callers found) | Verify no callers; deactivate; create/edit an Account and confirm no behaviour change. |
| 1.3 | **Delete obsolete flow versions** (e.g., `Account_is_Inactive` v3/v4; `Account_Object_Create_Edit_1` v1/v8/v11 drafts). | S | Very low | Confirm active version unchanged after cleanup. |
| 1.4 | **Add `ISCHANGED(Status__c)` entry criteria** to `Account_is_Inactive`. | S | Low–medium (changes when it fires) | See audit Phase 6, Change 2. |
| 1.5 | **Standardise documentation:** add flow-level `<description>` where missing (`Account_is_Inactive`) and rationale for the scheduled path in `_1`. | S | None | N/A (metadata only). |

## Phase 2 — Critical bug fixes (the embarrassing ones)

| # | Action | Effort | Risk | Test scenarios |
|---|---|---|---|---|
| 2.1 | **Add fault paths** to every active DML/subflow element: `Account_Object_Create_Edit_1` (14), `Account_is_Inactive`, `Update_Tax_Country_Code`, `Update_Account_Organisation_Type…`, `Lead_AL_UpdateGenericFields`. | M | Low (additive) | Audit Phase 6, Change 1. |
| 2.2 | **Remove hardcoded IDs.** Campaign Id in `Lead_AL_UpdateGenericFields` (`701Px…`) and RecordType Ids in `Quote_BeforeSave_UpdateQuoteFields` / `Task_AL_FirmUpdate` / `Gong…` → replace with CMDT/Custom Label or `$Record.RecordType.DeveloperName` comparisons. | M | Medium (behaviour-sensitive) | Verify the same records match by DeveloperName/label as by Id, in sandbox, across record types. |
| 2.3 | **Bound the Ultimate-Account cascade** (`_1` scheduled `myRule_18`): add pagination/row-limit guards + fault paths; or move to Apex if child volumes are high (**BUSINESS CONTEXT NEEDED** — max children per ultimate account). | M–L | High (touches 7 child objects) | Account with 10k+ children; verify no DML-limit failure; verify children get `Ultimate_Account__c`. |
| 2.4 | **Fix RecordType.Name → DeveloperName** in `_1` `Check_if_record_is_office_or_firm`. | S | Low | Firm/Office record-type accounts route correctly. |

## Phase 3 — Consolidation (merge into the master pattern)

| # | Action | Effort | Risk | Test scenarios |
|---|---|---|---|---|
| 3.1 | **Create `Account_Trigger_BeforeSave`** orchestrator and move same-record updates out of after-save: Tax Code (absorbing `Update_Tax_Country_Code`), Debtor flag, Shipping copy, both industry derivations (`Account_Update_Industry_Category` + `_1` Part1/Part2). | L | Medium–High | Audit Phase 6, Change 3; plus regression on debtor/shipping/industry fields. |
| 3.2 | **Create `Account_Trigger_AfterSave`** orchestrator; fold `Account_is_Inactive`, Push-to-Office, and the (bounded) Ultimate cascade into routed subflows. Resolve the **two-after-save-flows** violation. | L | High | Full Account create/edit regression; verify single, ordered after-save execution. |
| 3.3 | **Reconcile with `AccountTrigger` Apex** (API 64): define explicit order of execution between Apex and the master flows. | M | Medium | Confirm no double-processing or field clobbering. |

## Phase 4 — Architectural improvements

| # | Action | Effort | Risk | Test scenarios |
|---|---|---|---|---|
| 4.1 | **Introduce `Flow_Feature_Toggle__mdt`** (per-subflow `Is_Active__c` + global kill-switch); retire the three inconsistent `Application_Settings__c` checkboxes. | M | Low | Toggle each subflow off/on; confirm isolation. |
| 4.2 | **Move hardcoded picklist maps to `Industry_Mapping__mdt`** (Industry → Level One / Category, debtor statuses, firm-size thresholds). | M | Low–Medium | Mapping parity test vs current formula output across all industry values. |
| 4.3 | **Upgrade API versions to 60+** on all retained flows (currently several at 49/52/56/57). | S–M | Low | Re-test each flow after version bump. |
| 4.4 | **Extract reusable Formula resources / single industry element** instead of Part1/Part2 split. | M | Low | Industry Level One parity test. |

## Phase 5 — Documentation & naming standardisation

| # | Action | Effort | Risk |
|---|---|---|---|
| 5.1 | Rename migration-artifact elements (`myRule_1/3/5/…`) to intent-named (`Decision_TaxCode`, etc.). | S | Low |
| 5.2 | Adopt a naming convention: `Account_Trigger_<Context>` / `Account_Sub_<Job>`; document in a flow README. | S | None |
| 5.3 | Add element-level descriptions to all decisions/DML in retained flows. | S | None |

---

## Recommended sequencing & the "top 3"

Do **Phase 1 quick wins** immediately (cheap, de-risks the rest), then the **top 3 highest-impact fixes** below (full test plans in audit Phase 6):

1. **Fault paths across active Account DML flows** (2.1) — removes silent/unhandled failures org-wide.
2. **`ISCHANGED(Status__c)` on `Account_is_Inactive`** (1.4) — stops every account edit from re-flagging contacts and clobbering manual corrections.
3. **Tax Code → before-save, retire the re-query subflow** (part of 3.1) — eliminates 1 SOQL + 1 DML per account save and proves the before-save migration pattern before tackling the rest.

Then proceed Phase 2 → 3 → 4 → 5. Phases 2.3 and 3.x are gated on the two **BUSINESS CONTEXT NEEDED** answers:
- Max related-record volume per ultimate account (decides cascade: bounded flow vs Apex).
- Whether both industry taxonomies (`Industry_Level_One__c` and `Industry_Category_txt__c`) are actively consumed.
- Whether `Account_is_Inactive` should fire on every save or only on the Active→Inactive transition.
- Confirmation that `Sample_Flow_to_Debug` is safe to remove.

---

## Rollback posture (applies to all changes)
- This audit's **git baseline** captures the current active + retrieved versions; any flow can be restored by redeploying its prior version from the baseline commit.
- Prefer **toggle-gated** rollout (Phase 4.1) so individual logic can be disabled in seconds without deactivating a master flow.
- Make all changes in **KJDEV first**, validate-only deploy, then promote.
