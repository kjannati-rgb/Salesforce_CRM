# REV-57 — Phase 2: Unified PFC Orchestrator Design (KJDEV)

**Date:** 2026-06-10 · **Target:** build in `KJDEV` · **Status:** design only — no flows built yet.
**Inputs:** [Phase 0](ClaudeCode_Phase0_Audit_Findings.md) · [Phase 1 data model](ClaudeCode_Phase1_DataModel_Design.md) (deployed) · [D5](ClaudeCode_D5_Trigger_Mechanism_Findings.md).
**Decisions:** all closed — D1 `Product_Brand__c` ✅ · D2 mirror inbound ✅ · D3 lookup on newer ✅ · D4 backfill = separate ticket · D5 Option A (Pardot `NF - ` Task) ✅.

---

## 1. Goal & shape

Replace flow (1) `Create_Pardot_Form_from_Task` with a **single Task-triggered orchestrator** that handles **all four sources** (`NF - `, `PFC:`, `Lead scoring MQL`, `EVT`) via `PFC_Task_Mapping__mdt`, and adds the new behaviour: **cross-linking** open PFCs for the same person + brand through a **shared autolaunched subflow**.

Flows we **keep untouched**: (2) `On_Pardot_Form_Creation`, (3) `Pardot_Lead_Conversion`, (5) `Move_Lead_to_Contact_on_Pardot_Form`, and the Next-Contact reminder flow. Phase 0 confirmed they're source-agnostic.

```
Pardot completion action ──creates──> Task ("NF - …" / "PFC:" / "Lead scoring MQL" / "EVT")
        │ (after-save, +1 min scheduled path, batch 50)
        ▼
[ Orchestrator: Pardot_Create_PFC_Orchestrator ]  ← replaces flow (1)
   1 Resolve  → match prefix to CMDT row; resolve WhoId → Lead/Contact
   2 Create   → insert PFC (RT, Source, Product_Brand, Form_Name, Sales_Rep, Stage=New, Clay_Routed=false)
   3 Link WhoId → UPDATE PFC.Lead__c / Contact__c  ── fires flow (2): Name/Campaign/Account
   4 Check&Link (shared subflow) → find open same-person+brand PFC; set Related_Form_Completion__c
   5 (NO routing in-flow — Clay, operated by Ashton, owns Owner + Sales_Rep; orchestrator only sets Clay_Routed=false — D2)
```

---

## 2. Components to build (KJDEV)

| API name | Type | Role |
|---|---|---|
| `Pardot_Create_PFC_Orchestrator` | Flow (record-triggered, Task, after-save) | entry, kill-switch, resolve, create, link WhoId |
| `PFC_Resolve_Task_Mapping` | Flow (autolaunched, subflow) | Subject → matched CMDT row fields (RT devname, source, brand, parse rules) |
| `PFC_Check_And_Link` | Flow (autolaunched, subflow) | same-person+brand open-PFC match → set `Related_Form_Completion__c` |
| `PFC_Log_Fault` | Flow (autolaunched, subflow) | write `Flow_Log__c` on any DML fault (fail-open) |

> Modular subflows mirror the Contact-Role-Check rebuild pattern (CMDT-driven, Custom Error/bypass, fault logging). `PFC_Check_And_Link` is the literal "shared by every source" piece — the rebuild's point.

---

## 3. Orchestrator — `Pardot_Create_PFC_Orchestrator`

**Start:** object `Task`, `RecordAfterSave`, **Create** only. Preserve flow (1)'s **scheduled async path** (offset **+1 min** from `CreatedDate`, `maxBatchSize 50`) — proven bulk behaviour for the month-end surge.

**Entry filter (coarse gate):** `Subject StartsWith` one of `NF - ` / `PFC:` / `Lead scoring MQL` / `EVT`.
> Design note: a record-triggered start filter can't read CMDT, so the coarse prefix list is static here; the **precise** routing is CMDT-driven inside (step 1). Adding a brand-new prefix = one CMDT row **+** one line in this filter. (Alternative — fire on every Task and filter inside — rejected: Task create volume is high; the coarse gate avoids firing org-wide.)

**Kill switch:** honour `$Setup.Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` (same as flow (1)). Add a REV-57-specific bypass via the standard bypass permission/CS used in the Contact-Role rebuild if desired.

**Step 1 — Resolve** (calls `PFC_Resolve_Task_Mapping`, passing `$Record.Subject`):
- Get Records `PFC_Task_Mapping__mdt` WHERE `Active__c = true`, **sorted by `Match_Priority__c` asc**.
- Loop; first row where `BEGINS($Record.Subject, row.Subject_Prefix__c)` wins (set a `found` flag, ignore later rows). No DML/SOQL in the loop.
- If no match → exit (defensive; coarse gate should prevent this).
- Resolve RT: Get Records `RecordType` WHERE `SobjectType='Pardot_Form_Completion__c'` AND `DeveloperName = matched.Record_Type_DeveloperName__c` → Id. **No hardcoded RT Ids** (fixes flow (1)'s hardcoded formula).

**Step 2 — Create PFC** (Create Records, single):
| Field | Value |
|---|---|
| `RecordTypeId` | resolved RT Id |
| `PFC_Source__c` | `matched.Source__c` |
| `Product_Brand__c` | `matched.Default_Brand__c` (Newsfeed→`Lexology`; blank for inbound/MQL/EVT → derive via `Brand__c`) |
| `Form_Name__c` | see §5 (parse rules) |
| `Sales_Rep__c` | `$Record.OwnerId` (mirror inbound — D2) |
| `Sales_Stage__c` | `New` |
| `Clay_Routed__c` | `false` (explicit; lets Clay/RoE route — D2) |

> ⚠️ Do **NOT** set `Lead__c`/`Contact__c` in this insert (see §4).

**Step 3 — Link WhoId** (Decision on `$Record.WhoId StartsWith "00Q"`):
- Lead → Update PFC `Lead__c = $Record.WhoId`
- else → Update PFC `Contact__c = $Record.WhoId`

**Step 4 — Check & Link:** call `PFC_Check_And_Link` (§6).

Every DML element (Create, the two Updates, the link Update) gets a **fault connector → `PFC_Log_Fault`** then ends gracefully (fail-open — never lose the record). 

---

## 4. Why create-then-update WhoId (regression-critical)

Flow (2) `On_Pardot_Form_Creation` triggers on PFC **Update** when `Contact__c`/`Lead__c` **IsChanged**, and stamps `Name`, `Pardot_Form_Completion__c`, `Campaign__c`, `Account_Contact__c`. If the orchestrator set `Contact__c`/`Lead__c` in the **insert**, flow (2) (update-triggered) would **not fire** → Name/Campaign/Account never stamped → **inbound regression**.

Flow (1) avoids this by creating the PFC first, then doing a separate Update to set the WhoId link — which *is* the change that fires flow (2). **The rebuild must preserve this two-step pattern** so flow (2) keeps working and we leave it untouched. (Verified against Phase 4 test #8 "field-for-field identical".)

---

## 5. Form_Name parsing rules (CMDT-driven)

`Form_Name__c` = `IF(Parse_Form_Name_From_Subject__c, <stripped subject>, null)` where stripped subject removes the **left-anchored** prefix:
`IF(BEGINS(Subject, Strip) , MID(Subject, LEN(Strip)+1, LEN(Subject)) , Subject)` and if `Strip` is blank → full Subject.

| Source | Parse | Strip | Result | Matches legacy? |
|---|---|---|---|---|
| Inbound `PFC:` | true | `PFC:` | subject minus `PFC:` | ✅ flow (1) |
| Scored `Lead scoring MQL` | true | `Lead scoring MQL:` | subject minus prefix | ✅ flow (1) |
| Event `EVT` | **true** | *(blank)* | **full subject** | ✅ flow (1) else-branch |
| Newsfeed `NF - ` | false | — | **null** | new — never parse identity |

> **CMDT refinement to apply when building:** the Phase 1 seed set EVT `Parse=false`; change it to **`Parse=true`, `Strip=`(blank)** so EVT keeps its full-subject `Form_Name` exactly as flow (1) does today. Data-only change to `PFC_Task_Mapping.Event_Sponsorship`.

---

## 6. `PFC_Check_And_Link` (shared subflow) — the cross-link

**In:** new PFC Id, person type, LeadId/ContactId. **Re-query** the new PFC to read its resolved `Brand__c` (formula) and `Product_Brand__c`.

- `brandToMatch` = `IF(NOT ISBLANK(Product_Brand__c), Product_Brand__c, Brand__c)` (Newsfeed→`Lexology`; inbound→derived `Brand__c`).
- **Get Records** `Pardot_Form_Completion__c`, first record only, **ORDER BY `CreatedDate` DESC**, filter logic `1 AND 2 AND 3 AND (4 OR (5 AND 6))`:
  1. `Id != :newPfcId`
  2. person: `Lead__c = :leadId` *(Lead path)* **or** `Contact__c = :contactId` *(Contact path)* — branch by person type, one filter each
  3. `Sales_Stage__c IN ('New','Working','Nurturing')`
  4. `Product_Brand__c = :brandToMatch`
  5. `Product_Brand__c = null`
  6. `Brand__c = :brandToMatch`
- If a match is found → **Update new PFC** `Related_Form_Completion__c = match.Id`. The reverse direction needs no write — the older record's `Linked_Form_Completions` related list shows it (D3). **Always created regardless**; link is additive.

Symmetry holds (Phase 1 §6): a new Newsfeed (Product_Brand=`Lexology`) is later found by an inbound via filter 4; an open legacy inbound (`Brand__c=Lexology`, no Product_Brand) is found by a Newsfeed via filter 5+6.

**Bulk-safety:** all Get Records/DML are flow elements outside loops → the engine bulkifies them across the +1-min batch. No SOQL/DML inside any loop. The only loop (CMDT prefix match in Resolve) iterates ~4 in-memory rows.

---

## 7. Fault handling — `PFC_Log_Fault`

Mirror "Check Contact Role Log Faults": on any DML fault, write a `Flow_Log__c` row (flow name, `$Flow.FaultMessage`, Task Id, Subject) and continue (fail-open). Its own DML fault path is silent. No record is ever lost to a downstream validation block (Phase 4 #10).

---

## 8. Cutover (Phase 5 preview — not now)

1. Deploy orchestrator + 3 subflows **inactive** to KJDEV → test (Phase 4) → demo.
2. Prod: deploy inactive → in one window **activate orchestrator + deactivate flow (1)** → confirm Pardot `NF - ` Task config live → smoke-test one real subscription.
3. Flows (2)/(3)/(5)/reminder untouched. RT stays `Newsfeed_Subscribers`.

---

## 9. Maps to Phase 4 test plan
- #1 NF no existing PFC → created, source=Newsfeed, brand=Lexology, no link.
- #2/#3 NF↔inbound same brand open → created **and** linked (both directions via §6 symmetry).
- #4 existing Converted/Disqualified → created, no link (stage filter).
- #5 different brand → created, no link.
- #6 hyphenated name → correct (no subject identity parsing; person from WhoId).
- #7 200 NF tasks → bulk-safe (§6).
- #8 inbound regression → identical (§4 + §5 preserve flow (1) + flow (2)).
- #9 non-matching prefix → coarse gate + Resolve no-match → no PFC.
- #10 DML fault → `PFC_Log_Fault`, no silent loss (§7).

---

## 11. Design review & hardening (v2 — 2026-06-10)

Critique pass + Kam's lead-conversion bug reshaped the architecture. **Folded into the build:**

- **Check&Link becomes its own PFC-record-triggered flow** (`PFC_Check_And_Link`, after-save, entry = create **OR** `Lead__c`/`Contact__c` IsChanged) — NOT a step inside the orchestrator. Benefits: links any PFC regardless of creation path; **auto-re-evaluates after the conversion relink**; clean separation (Task flow creates, PFC flow links). Recursion-safe: it writes `Related_Form_Completion__c` only (not Lead/Contact), so it won't re-trigger itself.
- **NEW companion flow `PFC_Relink_Lead_to_Contact_on_Conversion`** (Lead, after-save, entry `IsConverted` newly true) — finds PFCs `Lead__c = thisLead, Contact__c = null` and bulk-sets `Contact__c = ConvertedContactId`, clears `Lead__c`. **Fixes the live bug**: the legacy `Move_Lead_to_Contact_on_Pardot_Form` (flow 5) is PFC-*update*-triggered + `Draft`, so it never reacts to conversion — only to a later stage edit. The new flow reacts to the actual Lead conversion event (works for native conversion, not just the Convert button), bulk-safe, fail-open. Legacy flow 5 stays Draft/deprecated.
- **Exclude `Brand = "Other"`/blank** from the match (§6): prevents false-positive links between unrelated "Other" inbounds for the same person. If `brandToMatch` ∈ {blank, `Other`} → skip linking.
- **Fail-open faults**: after-save flows that fault roll back the *triggering* DML (e.g., the Lead conversion!). Every DML has a fault path that swallows the error (→ `Flow_Log__c` once `PFC_Log_Fault` exists; no-op swallow until then).

**Deferred (documented fast-follows, not in this build):**
- Email (`Email__c`) fallback for person matching — over-match risk on shared/free-mail domains; do deliberately post-deadline. Conversion-relink closes most of the gap.
- Check&Link as invocable **Apex + unit tests** — better CI story; org convention is Flow+CMDT; revisit post-go-live.
- Near-simultaneous-forms race (two forms in one +1-min batch may not see each other) — reconciliation pass later.
- Open-stage set to CMDT — kept as a flow constant with a comment for now (minor).

**Revised component list:** `Pardot_Create_PFC_Orchestrator` (Task: resolve+create+link-WhoId, no Check&Link), `PFC_Resolve_Task_Mapping` (sub), `PFC_Check_And_Link` (**PFC-triggered**), `PFC_Relink_Lead_to_Contact_on_Conversion` (**Lead-triggered, NEW**), `PFC_Log_Fault` (sub).

## 10. Open implementation questions (flag before build)
- **Q1 — bypass:** reuse the Contact-Role-Check bypass permission/CS, or just the existing `Disable_Autolaunch_Lightning_Flow__c`? (Recommend: reuse both — global CS + a REV-57 permission for targeted testing.)
- **Q2 — multiple open matches:** §6 links the **most recent** open match only (single lookup, D3). Confirm that's the desired pick vs oldest.
- **Q3 — EVT CMDT refinement** (§5) — confirm preserve EVT full-subject `Form_Name` (recommended for regression).
