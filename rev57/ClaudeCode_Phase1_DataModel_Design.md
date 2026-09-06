# REV-57 — Phase 1 Data-Model Design (KJDEV)

**Date:** 2026-06-10 · **Target:** build in `KJDEV` · **Status:** design only — no org writes yet.
**Inputs:** [Phase 0 findings](ClaudeCode_Phase0_Audit_Findings.md). All facts below already re-verified against prod in Phase 0.

> Scope of this doc: the **data model** the Phase 2 flow rebuild stands on — new fields, the source/brand stamp, the cross-link lookup, the CMDT, and the record-type rename. Flow mechanics are Phase 2; this doc only specifies the *contract* the flow must satisfy (esp. the match-key semantics in §6).

---

## 1. What we're adding (overview)

| # | Component | Type | Purpose | Decision |
|---|-----------|------|---------|----------|
| 1 | `Product_Brand__c` | Picklist | Filterable brand-grain stamp; enables cross-link matching that `Brand__c` (formula→"Other" for NF) cannot | **D1** |
| 2 | `PFC_Source__c` | Picklist | Provenance of the record (Inbound / Newsfeed / …); replaces "infer from subject" | new |
| 3 | `Related_Form_Completion__c` | Lookup(self) | The cross-link; child rel `Linked_Form_Completions` shows reverse direction free | **D3** |
| 4 | `PFC_Task_Mapping__mdt` | CMDT | Prefix → RT / source / brand / parse rules. New sources = config rows, not flow edits | new |
| 5 | ~~RT rename `Newsfeed_Subscribers` → `Newsfeed_Registrations`~~ | RecordType | **DROPPED 2026-06-10** (Kam): cosmetic only, not mandatory; deploy can't rename a DeveloperName anyway. RT stays `Newsfeed_Subscribers`; CMDT points at it. | dropped |

Phase 0 cleared the rename as **safe** (no Apex/active-flow/declarative refs). Items 1–4 are additive (no existing-data side effects).

---

## 2. `Product_Brand__c` — brand-grain stamp (D1)

- **Type:** Picklist, optional, not required, no default (flow stamps it).
- **Values** (mirror the canonical set the `Brand__c` formula already produces):
  `Lexology`, `GAR`, `GCR`, `GIR`, `GRR`, `GDR`, `Latin Lawyer`, `GBRR`, `IAM`, `WTR`, `Other`.
- **Why a new field, not extending `Brand__c`:** `Brand__c` is a formula off `Form_Name__c`. Newsfeed records have `Form_Name__c = null` (we are forbidden to parse identity from the subject), so `Brand__c` is permanently `"Other"` for them. A stamped, filterable picklist is the only way to give newsfeed a real brand for matching. (Confirmed in Phase 0 §3.)
- **Population:** Newsfeed → always `"Lexology"` (from CMDT `Default_Brand__c`). Inbound/MQL/EVT → see §6 on whether we stamp it or rely on the legacy `Brand__c` for matching.

## 3. `PFC_Source__c` — provenance

- **Type:** Picklist, optional.
- **Values:** `Inbound Form`, `Scored Lead`, `Event`, `Newsfeed`, `Import` (last is future-proofing per runbook).
- Set from CMDT `Source__c` on the matched prefix. Lets reps/list views/reporting split newsfeed from inbound without record-type gymnastics.

## 4. `Related_Form_Completion__c` — the cross-link (D3)

- **Type:** `Lookup(Pardot_Form_Completion__c)`, optional.
- **Child relationship name:** `Linked_Form_Completions` · **label:** "Linked Form Completions".
- **Model (recommended, matches runbook):** populate the lookup on the **newer** record pointing at the older open match. The reverse direction needs **no second field** — the older record's **related list** "Linked Form Completions" surfaces it automatically. One write, both records visibly linked.
- **Symmetry:** whichever record is created second points back; works newsfeed→inbound *and* inbound→newsfeed.
- **Layout:** add the "Linked Form Completions" related list to both Newsfeed Registrations and Form Completion record pages (Phase 3).

## 5. `PFC_Task_Mapping__mdt` — config-driven prefix routing

Custom Metadata Type. One row per task-subject prefix. **Replaces the hardcoded formulas in flow (1)** (which used CONTAINS + hardcoded RT IDs — Phase 0 §2).

**Fields:**

| Field | Type | Notes |
|---|---|---|
| `Subject_Prefix__c` | Text(80) | Left-anchored match (`StartsWith`). e.g. `NF - ` |
| `Record_Type_DeveloperName__c` | Text(80) | Resolved to RT Id at runtime via Get Records (no hardcoded IDs — NFR) |
| `Source__c` | Text(40) | → `PFC_Source__c` |
| `Default_Brand__c` | Text(40) | → `Product_Brand__c` when set (NF = `Lexology`); blank = derive/leave |
| `Parse_Form_Name_From_Subject__c` | Checkbox | **false for Newsfeed** (never parse identity); true for inbound/MQL |
| `Form_Name_Prefix_To_Strip__c` | Text(40) | When parsing, prefix to strip (e.g. `PFC:`, `Lead scoring MQL:`) |
| `Match_Priority__c` | Number(2,0) | Order to test prefixes (lowest first) — guards future overlap |
| `Active__c` | Checkbox | Toggle a source without touching the flow |

**Seed rows (mirror current flow (1) + add Newsfeed):**

| Label | Subject_Prefix__c | Record_Type_DeveloperName__c | Source__c | Default_Brand__c | Parse_Form_Name | Strip prefix | Active |
|---|---|---|---|---|---|---|---|
| Inbound Form | `PFC:` | `Form_Completion` | Inbound Form | *(blank — derive)* | ✅ | `PFC:` | ✅ |
| Scored Lead | `Lead scoring MQL` | `Scored_Leads` | Scored Lead | *(blank)* | ✅ | `Lead scoring MQL:` | ✅ |
| Event Sponsorship | `EVT` | `Events_Sponsorship` | Event | *(blank)* | ❌ (keep full subject)* | — | ✅ |
| Newsfeed | `NF - ` | `Newsfeed_Registrations` | Newsfeed | `Lexology` | ❌ | — | ✅ |

\* Current flow's `else` branch leaves EVT's Form_Name as the full subject — replicate via `Parse_Form_Name=false` / no strip.

> The four prefixes don't overlap, so `StartsWith` is unambiguous; `Match_Priority__c` is insurance for future additions. **To replace flow (1) at cutover the orchestrator must honor all four rows** — not just Newsfeed (Phase 0 §2).

## 6. Match-key semantics (the contract Phase 2 must implement)

Cross-link rule: *on create, if an open PFC exists for the **same person + same brand** in an **open stage**, create the new record anyway and link the two.*

- **Person grain:** same `Lead__c` **or** same `Contact__c` value (taken from Task `WhoId`).
  *Limitation:* a Lead and its converted Contact are different Ids; we do **not** bridge lead↔contact identity. Match is on the literal Lead__c / Contact__c value. (Flag for D-review; bridging is out of scope.)
- **Open stage set:** `Sales_Stage__c IN ('New','Working','Nurturing')`.
- **Brand grain — the subtle part.** New records get `Product_Brand__c`; the ~61k legacy records only have the `Brand__c` formula. To match across both, the Check-&-Link query filters:

  ```
  ( Product_Brand__c = :brand  OR  ( Product_Brand__c = null AND Brand__c = :brand ) )
  ```

  - `:brand` for the *incoming* record = its `Default_Brand__c` if set (Newsfeed→`Lexology`), else its resolved `Brand__c`.
  - This makes linking **symmetric**: a new Newsfeed record (Product_Brand__c=`Lexology`, Brand__c=`Other`) is found by a later inbound via `Product_Brand__c`; an open legacy inbound (Brand__c=`Lexology`) is found by a Newsfeed via the `Brand__c` fallback. Without the new field the reverse direction is impossible (Phase 0 §3).
- **Always create**, then link — never suppress the new record.

## 7. Record-type rename — DROPPED

**Decision 2026-06-10 (Kam): leave the record type as `Newsfeed_Subscribers`.** The rename was cosmetic (Phase 0 proved zero references, so nothing breaks either way) and a metadata deploy can't rename a DeveloperName regardless (it creates a duplicate — see [gotchas memory]). The Newsfeed CMDT row's `Record_Type_DeveloperName__c` is set to **`Newsfeed_Subscribers`** accordingly. If the label "Newsfeed Registrations" is ever wanted, that's a safe label-only deploy or a 20-sec UI edit, done independently.

**Picklist value assignments** for the new fields, per-RT availability:
- `Product_Brand__c`: all values available on Newsfeed Registrations + Form Completion RTs.
- `PFC_Source__c`: `Newsfeed` on the NF RT; `Inbound Form`/`Scored Lead`/`Event` on their RTs.

---

## 8. Resolved decisions (defaults flagged for Kam)

| # | Decision | Recommendation | Status |
|---|----------|----------------|--------|
| **D1** | Product/brand stamp | **New `Product_Brand__c` picklist.** Not optional — it's a *hard dependency* of symmetric cross-linking (Phase 0 §3). | ✅ resolved |
| **D2** | Newsfeed assignment | **RESOLVED 2026-06-10 (Kam): mirror inbound.** `Sales_Rep__c = NF Task.OwnerId`, `OwnerId` left to creating context, `Clay_Routed__c = false` → newsfeed flows through the same Clay/ROE routing as inbound. (Current model: flow stamps Sales_Rep at create; Clay+RoE is the real router, no SF assignment rules/queues.) | ✅ resolved |
| **D3** | Linking model | **Single lookup on newer record** + related list both sides. | ✅ resolved |
| **D4** | Null-RT backfill (47k) | **Yes, but separate ticket** — data job, not REV-57. | ✅ deferred |
| **D5** | Pardot side / trigger source | **RESOLVED 2026-06-10 (Kam): Option A — a new Pardot-created `NF - ` Task** (not yet configured in Pardot; planned for go-live). All four sources are Task-driven → **unified Task-triggered orchestrator replacing flow (1)**, subject-prefix CMDT applies natively. ([D5 findings](ClaudeCode_D5_Trigger_Mechanism_Findings.md)) | ✅ resolved (Pardot config build still owed) |

---

## 9. Build order (when greenlit — KJDEV, no prod)

1. Fields: `Product_Brand__c`, `PFC_Source__c`, `Related_Form_Completion__c`.
2. CMDT `PFC_Task_Mapping__mdt` + 4 seed records.
3. ~~RT rename~~ — dropped (§7). RT stays `Newsfeed_Subscribers`.
4. Hand off to Phase 2 (flow) — gated on **D5** and **D2** confirmation.

**Phase 1 build status (2026-06-10): DEPLOYED & VERIFIED in KJDEV.** Dry-run 16/16 → real deploy 16/16, 0 errors; CMDT rows read back correct; Newsfeed row repointed to `Newsfeed_Subscribers`.

**Nothing here is destructive or prod-bound.** All additive in KJDEV; the only rename is a label/DeveloperName change on an RT with zero inbound references.
