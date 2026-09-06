# OCR / CPQ Renewal Failure — Read-Only Discovery

**Org:** Law Business Research — PROD (`00D6g0000081IOgEAM`, `lawbusinessresearch.my.salesforce.com`)
**Connected as:** kamyar.jannati@lbresearch.com (alias `PROD`)
**Date:** 2026-06-27
**Scope:** Discovery only. No metadata, data, or config was modified. Metadata retrieved into a throwaway SFDX project in scratch space; active flow versions read via the Tooling API.

---

## TL;DR (root cause)

CPQ renewal opportunities silently fail for a subset of contracts because **two independent automations both insert the *same* `[Opportunity, Contact, Role]` OpportunityContactRole (OCR) row inside the one renewal-creation transaction**, and an **after-save record-triggered Flow guard throws a Custom Error on the duplicate, rolling the entire transaction back** — so the renewal Opportunity, its Quote and Quote Lines are never committed.

- **THE GUARD** — Flow `Opportunity_Contact_Role_Check_for_Duplicate` (active **v7**), after-save on `OpportunityContactRole`, throws *"This is an duplicate contact role, please use existing contact role"* when another OCR exists with the **same OpportunityId + ContactId + Role** (excluding itself).
- **THE GENERATOR(S)** — On a renewal, CPQ's native **`SBQQ__DefaultRenewalContactRoles__c = true`** clone (on **41,508 of 41,511** Contracts) copies the source-opp OCRs onto the renewal opp, **and** Flow `Opportunity_Renewal_New_Records` (active v9) *also* creates a `Decision Maker` / `IsPrimary` OCR for `Primary_Contact__c` with **no check for an already-existing matching role**. When the cloned primary role is also `Decision Maker`, the two collide → guard fires → rollback. A sibling anti-pattern, Flow `Add_Contact_Roles_on_Amendments` (active v3), copies *all* roles from the cancelled opp onto amendment opps with no dedupe, driving the broader same-contact-multiple-role proliferation.

There is **no Apex trigger on OpportunityContactRole** and **no validation rule** enforcing this — it is entirely Flow-driven.

---

## 1. Inventory — everything firing on OpportunityContactRole insert/update

| Artifact | Type / Trigger | Active? | Purpose (one line) |
|---|---|---|---|
| `Opportunity_Contact_Role_Check_for_Duplicate` | Flow, after-save on **OCR** (Create+Update) | **v7 Active** (v9 Draft exists) | **THE GUARD** — throws Custom Error on duplicate `[Opp, Contact, Role]` |
| `Opportunity_Contact_Role_Create` | Flow, after-save on **OCR** (Create+Update) | v6 Active | Stamps `Opportunity.Primary_Contact__c` from the `Decision Maker` OCR. Does **not** create OCRs. |
| `Opportunity_Renewal_New_Records` ("Opportunity_AL_FieldUpdates") | Flow, on **Opportunity** | v9 Active | **GENERATOR** — creates a `Decision Maker`/`IsPrimary` OCR for `Primary_Contact__c` (see §3) |
| `Add_Contact_Roles_on_Amendments` | Flow, after-save on **SBQQ__Quote__c** Create (Type = Amendment) | v3 Active | **GENERATOR** — copies every OCR from `Cancelled_Opportunity__c` onto the amendment opp, **no dedupe** (see §3) |
| CPQ native renewal clone | SBQQ managed package | Contract field `SBQQ__DefaultRenewalContactRoles__c` = true on **41,508/41,511** Contracts | **GENERATOR** — clones source-opp OCRs verbatim onto the renewal opp at renewal-forecast time |
| `Check_Completeness_of_Contact_Roles` | Flow, before-save on Opportunity (reads OCR) | Active | Stamps `Has_Contact_Role__c` / `Has_Complete_Contact_Role__c`. Read-only on OCR. |
| `Opportunity_Contact_Role_Create_Edit` | Flow on OCR | **Obsolete** (v2) | Not firing |
| `Add_Contact_Roles_to_Opportunity` | Flow on OCR | **Obsolete** (v1) | Not firing |
| `Create_Opportunity_Contacts` | Flow | **Obsolete** (latest v21) | Not firing |
| `Gong__Gong_for_Salesforce_Create_Contact_Role` | Managed (Gong) | Active | Gong-sourced OCRs (separate integration path; not implicated in the renewal stream) |
| `ContactRoleCheckRecompute.cls` | Apex batch | n/a | Read-only backfill of the two Opportunity flags; **does not** create/guard OCRs |
| Apex triggers on OpportunityContactRole | — | **None exist** | Confirmed: no `trigger ... on OpportunityContactRole` in the org |
| Validation rules on OpportunityContactRole | — | **None retrieved** | A VR cannot count sibling rows; not the guard |

---

## 2. THE GUARD

**File / artifact:** Flow `Opportunity_Contact_Role_Check_for_Duplicate`
- Retrieved (latest = v9, **Draft**): `force-app/main/default/flows/Opportunity_Contact_Role_Check_for_Duplicate.flow-meta.xml`
- **Active version = v7** (read via Tooling API — the source-format retrieve returns the latest/Draft v9, *not* the running v7). v7 and v9 enforce the same key but with different element shapes (v7 = single filtered lookup + null check; v9 Draft = loop + per-row compare).

**Trigger:** `RecordAfterSave`, `recordTriggerType = CreateAndUpdate`, object `OpportunityContactRole`.

**Disable switch:** formula `var_disableflow = $Setup.Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c`. If true, the flow exits without checking (the org-standard kill switch).

**Exact logic (active v7):**
1. `Check_if_flow_is_Disabled` — if the org kill switch is on, stop.
2. `Get_Contact_Role` — query `OpportunityContactRole` with **all** of:
   - `OpportunityId = $Record.OpportunityId`
   - `ContactId = $Record.ContactId`
   - `Id ≠ $Record.Id`
   - `Role = $Record.Role`
3. `Record_Found` decision — if that query returned anything (`Get_Contact_Role` IsNull = false) →
4. `Custom_Validation` **Custom Error** element fires.
5. (Also calls subflow `Flow_log_v3` → writes a `Flow_Log__c` audit row each run.)

**Key field(s):** keyed on the triple **OpportunityId + ContactId + Role** (NOT ContactId alone, and NOT IsPrimary). It blocks an exact repeat of the same role for the same contact on the same opp.

**Verbatim error message:**
> `This is an duplicate contact role, please use existing contact role`

Because this is an **after-save Custom Error**, throwing it aborts and **rolls back the whole DML transaction** that inserted the OCR — including, during a renewal, the renewal Opportunity + Quote + Quote Lines created in that same transaction.

**Evidence it is live and firing:** `Flow_Log__c` holds **972** rows with `Flow_Name__c = 'Opportunity Contact Role: Check for Duplicate'` (the audit subflow logs each execution). Org-wide there are **0** surviving true `[Opp, Contact, Role]` duplicate triplets created in the last 60 days — i.e., the guard is successfully preventing every exact-pair duplicate from persisting (and, as a side effect, killing the transactions that attempt them).

---

## 3. THE GENERATOR(S)

### 3a. `Opportunity_Renewal_New_Records` (v9 Active) — primary collision source
**File:** `force-app/main/default/flows/Opportunity_Renewal_New_Records.flow-meta.xml` (internal label *Opportunity_AL_FieldUpdates*), record-triggered on **Opportunity**.

- Decision `Create_Opportunity_Contact_Role2` → create only when `Primary_Contact__c` is NOT null **AND** `Pardot_Form_Completion__c` is NOT null.
- `Create_Opportunity_Contact_Role` inserts an OCR:
  - `ContactId = recordId.Primary_Contact__c`
  - `OpportunityId = recordId.Id`
  - `IsPrimary = true`
  - `Role = "Decision Maker"` (hard-coded)
- **Bug:** no Get/decision checks whether an OCR for that contact already exists on the opp. On a renewal opp that CPQ has *also* populated via the contact-role clone, this produces a **second** `[renewalOpp, primaryContact, "Decision Maker"]` row.

### 3b. CPQ native renewal clone (`SBQQ__DefaultRenewalContactRoles__c`) — the other half of the collision
- Distribution: `true` on **41,508** Contracts, `false` on **3**. Renewal OCR-cloning is effectively universal; it is the managed-package field default, set per-Contract, not gated.
- At renewal-forecast time CPQ clones the source opp's OCRs verbatim onto the renewal opp, including the primary contact's role. If that cloned role is `Decision Maker`, it is identical to what 3a inserts.

**Net effect / the duplicate:** within the single renewal transaction, 3a and 3b each insert `[renewalOpp, primaryContact, "Decision Maker"]`. The two inserts land at the **same instant** (one transaction → identical `CreatedDate` to the second) — this is the "double-insert at identical timestamp" fingerprint. The after-save guard (§2) sees the sibling and throws → rollback → **renewal opp never created**. It fails only when the cloned primary role equals `Decision Maker`, which is why only *some* contracts are affected.

### 3c. `Add_Contact_Roles_on_Amendments` (v3 Active) — same anti-pattern, amendment path
**File:** `force-app/main/default/flows/Add_Contact_Roles_on_Amendments.flow-meta.xml`, after-save on **SBQQ__Quote__c** Create where `SBQQ__Type__c = 'Amendment'`.

- `Get_Contact_Roles_from_Opp` — reads **all** OCRs where `OpportunityId = $Record.SBQQ__Opportunity2__r.Cancelled_Opportunity__c` (the original/cancelled opp).
- Loops and `Create_New_Contact_Role` copies each onto `$Record.SBQQ__Opportunity2__r.Id` (the amendment opp): `ContactId`, `Role`, `IsPrimary`, `CurrencyIsoCode`, `Original_Account__c`.
- **Bug:** no dedupe against OCRs already on the amendment opp. Re-amending, or any opp that already carries roles, doubles them. This is the main driver of the broader *same-contact-with-multiple-roles* proliferation seen in the data (it is only *not* caught by the guard when the copied roles differ from existing ones).

### CreatedBy evidence (the live stream)
Query on the three flagged opps (`006Px00000RhS6LIAV`, `006Px00000SJi5FIAT`, `006Px00000SN9aLIAT`):
- All OCRs on a given opp share an **identical `CreatedDate` to the second** → created in **one transaction / bulk insert**, the automated fingerprint.
- `CreatedBy.Name` = **Saurabh Patil** (`0054L000003kLUGQA2`), a **System Administrator** (Standard user) — i.e., the inserts run in the context of the admin whose action/job (renewal forecast, amendment, or contract activation) drove the transaction, **not** an integration user (Groove/Pardot/ZoomInfo) and **not** the Automated Process user.
- On these surviving opps every contact's rows carry **distinct roles** (e.g. `0034L00000oAzdVQAS` = *Influencer* + *Business User*; `003Tm000007qndLIAQ` = *Business User* + *Decision Maker*). That is exactly what you'd expect when the guard has stripped the exact-role collisions but left the multi-role rows — and is consistent with 0 surviving exact-triplet duplicates org-wide.

### 3d. `Opportunity_Contact_Role_Create` (v6 Active) — the "Decision Maker" normalizer (added 2026-06-27)
After-save on OpportunityContactRole (Create+Update). On `$Record.IsPrimary = true` it runs two updates:
- **force-overwrites `$Record.Role = "Decision Maker"`** (it does not preserve the role that was inserted/cloned), and
- sets `$Record.Opportunity.Primary_Contact__c = ContactId`.

**Why this matters to the root cause:** it *manufactures* the collision. Because every primary OCR is normalized to `Decision Maker`, and the renewal flow (§3a) also hard-codes `Decision Maker`, and CPQ clones the (now-normalized) primary role, the duplicate the guard trips on is near-**deterministically** `[Opp, Contact, "Decision Maker"]` — not a coincidence of data. This is upstream of the dual-writer collision.

**Kill-switch caveat:** this flow is **not** gated by `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` (the switch the guard and amendment flow honor). It is gated by a **separate legacy switch, `Application_Settings__c.Disable_Process_Builders__c`** (it was migrated from a Process Builder). There are therefore **two divergent OCR kill switches** — any insert-based backfill or controlled cleanup must disable **both** to fully quiesce OCR automation. (The async reconciler is unaffected: it only deletes, and no OCR automation fires on delete.)

---

## 4. Duplicate-PERSON case (same human as two Contact records)

**Not covered — separate gap.** The guard keys on `ContactId`. If the same human exists as two different `Contact` records (e.g., a duplicate created by Pardot/Lead conversion), each has a distinct `ContactId`, so two OCRs for "the same person" in the same role are **not** flagged as duplicates and will clone freely onto renewals. None of the three generators dedupe on person identity either. This is a distinct data-quality problem from the `[Opp, Contact, Role]` collision above and would need its own match-key/merge remediation.

---

## 5. Root-cause statement

CPQ renewal generation runs **two uncoordinated OCR writers in the same transaction** — the managed-package `DefaultRenewalContactRoles` clone (universally on) and the `Opportunity_Renewal_New_Records` flow's hard-coded `Decision Maker`/primary insert — neither of which checks for an existing matching role. When their roles coincide (`Decision Maker`), the **after-save guard `Opportunity_Contact_Role_Check_for_Duplicate` throws a Custom Error on the duplicate `[Opp, Contact, Role]`, which rolls back the entire renewal transaction**, so the renewal Opportunity is silently never created. The amendment-path flow `Add_Contact_Roles_on_Amendments` exhibits the same no-dedupe anti-pattern and feeds the broader duplicate-OCR proliferation.

---

## 6. Candidate fix locations (NOT implemented)

1. **`Opportunity_Renewal_New_Records` (v9)** — before `Create_Opportunity_Contact_Role`, add a Get Records on OCR for `OpportunityId = recordId.Id AND ContactId = recordId.Primary_Contact__c AND Role = 'Decision Maker'` and only create when none found (upsert-style). Most surgical fix; removes the primary collision with the CPQ clone.
2. **CPQ native clone vs flow** — decide on a single owner of the renewal primary OCR. Either (a) let CPQ's `DefaultRenewalContactRoles` own it and stop the flow from creating one on renewal-type opps, or (b) turn the clone off for the primary role. Avoid both writing it.
3. **`Add_Contact_Roles_on_Amendments` (v3)** — add a dedupe Get/decision so it copies a role only if an equal `[Opp, Contact, Role]` does not already exist on the target opp.
4. **The guard itself** — consider making it *idempotent/silent* for automated contexts (e.g., dedupe-and-delete the extra row, or skip-not-throw) instead of a hard Custom Error that rolls back unrelated records. A non-blocking guard would stop killing renewals while still preventing dupes. (The v9 Draft is a candidate rewrite — review before activating; it currently keys the same way.) The org kill switch `Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c` can suppress it during a controlled backfill.
5. **Duplicate-person gap (§4)** — separate remediation: contact match-key/merge, out of scope for the renewal collision.
6. **Data cleanup** — backfill/dedupe existing multi-role OCRs created by 3a/3c so future renewal clones don't carry collisions forward (run under the kill switch).

---

### Appendix — commands used (read-only)
- `sf org list` / `sf org display -o PROD` — confirmed target org.
- `sf project retrieve start -o PROD -m ApexTrigger ApexClass` — Apex (no OCR trigger; only `ContactRoleCheckRecompute` + tests reference OCR).
- `sf org list metadata -m Flow -o PROD` → filtered, then retrieved the contact-role / renewal / customer-journey flows.
- Tooling API `FlowDefinition` / `Flow` queries — active-version numbers and the active-version metadata JSON for the guard (v7) and generators (v3, v6).
- SOQL: OCR rows on the 3 flagged opps (CreatedBy = Saurabh Patil, System Administrator; identical per-opp timestamps); aggregate `[Opp, Contact, Role]` HAVING COUNT > 1 (0 surviving); `Flow_Log__c` count for the guard (972); `Contract.SBQQ__DefaultRenewalContactRoles__c` distribution (41,508 true / 3 false).
