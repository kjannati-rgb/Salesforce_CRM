# REV-68 — LBR Interactions on Lead records (KJDEV build report)

Target org: `kamyar.jannati@lbresearch.com.kjdev` (sandbox). **Production was not a deploy target.** Built 2026-06-11.

---

## 1. Impact-list findings (audit before execute)

The kickoff assumed a pre-built package, but the supplied zip was a 1-byte placeholder and the two temp files had swapped contents. Ground truth from the org differed materially:

| Kickoff assumption | Reality in KJDEV | Action taken |
|---|---|---|
| `Contact__c` is a relaxable **required** field | It is **Master-Detail** (no `required` flag to flip) | Converted **Master-Detail → Lookup** (the real change REV-68 needs) |
| `Lead__c` lookup exists | Did **not** exist | Created (Lookup, SetNull) |
| `Interaction_Code__c` external Id exists | Did **not** exist | Created (Text 80, unique, case-insensitive, external Id) |
| VRs `Contact_or_Lead_Required`, `Block_Converted_Lead` exist | Neither existed (only `Opportunity_mandatory_for_LexPro`) | Authored both |
| Perm set `LBR_Interactions_on_Leads` exists | Did **not** exist | Created + assigned to running user |

**🚩 Blocker found and flagged (paused for decisions):** a roll-up summary **`Contact.Count_of_LBR_Interactions__c`** existed, which *requires* the Master-Detail relationship — Salesforce blocks MD→Lookup while it exists. This is exactly the "rollup that assumes Contact is always populated" the kickoff said to flag.

**Decisions taken (with the user):**
- **MD→Lookup** on the single object (best-in-class vs a separate Lead-side object: one report/history, reparent is a field-update not a record-copy, matches the org's existing `Account__c`/`Ultimate_Account__c` lookup convention).
- Roll-up **replaced with a maintained count** — a Number field of the same API name kept current by a new trigger.
- New org-wide default for the (now standalone) object: **Public Read/Write**.

Other facts confirmed during audit: 0 `LBR_Interactions__c` records in KJDEV (conversion data-safe); `Ultimate_Account__c` is auto-populated from the **parent Account's** `Ultimate_Account__c` (per `UltimateAccountBeforeSaving`); lookup filters — interaction `Account__c` requires Office RT, `Account.Ultimate_Account__c` requires Firm RT; the convert hook is the existing `LeadConvertInvocable` `@InvocableMethod`.

---

## 2. What was built & deployed (all succeeded in KJDEV)

**Schema**
- `Contact__c`: Master-Detail → **Lookup** (`required=false`, `deleteConstraint=SetNull`).
- Object OWD: `ControlledByParent` → **Public Read/Write** (internal) / Private (external).
- `Lead__c` (Lookup→Lead, SetNull), `Interaction_Code__c` (Text 80, unique CI, external Id).
- VR **`Contact_or_Lead_Required`** — XOR: exactly one of Contact/Lead (fires on neither or both).
- VR **`Block_Converted_Lead`** — fires when `Lead__c` is set and `Lead__r.IsConverted`.
- Removed roll-up `Contact.Count_of_LBR_Interactions__c`; recreated it as a Number field maintained by the `LBRInteractionCount` trigger.
- Perm set **`LBR_Interactions_on_Leads`** (object CRUD + FLS), assigned to the running user.

**Apex** (all live, tests green)
- **`LBRInteractionReparentService`** — reusable. Per lead-side interaction: dedup against the target Contact (same `Interaction_Code__c`, else same Type+Product+Date) → delete the duplicate; otherwise re-parent (`Contact__c`, `Account__c`, `Ultimate_Account__c` = parent Account's ultimate) and **clear `Lead__c` in the same DML** (so neither VR fires). Inserts `Contact2Interaction__c` (Contact, Interaction, Opportunity) for survivors when an Opp was created, skipping existing pairs. Single queries/DML; bulk-safe for 200.
- **`LBRInteractionConvertSweeper`** — schedulable daily batch over `Lead__c != null AND Lead__r.IsConverted = true`; reuses the service. Catches converts that bypass the invocable.
- **`LeadConvertInvocable`** — extended to call the service after a successful `Database.convertLead`.
- **`LBRInteractionCount` trigger / `LBRInteractionCountHandler`** — maintains the replacement count field on insert/update/delete/undelete.

**UI**
- LBR Interactions layout: added `Lead__c` + `Interaction_Code__c`; changed `Contact__c` from Required → Edit (it's optional now).
- `Lead-Lead Layout`: added the **LBR Interactions** related list (columns: Interaction Type, Product, Interaction Date, Interaction Status, End Date).

---

## 3. Test results & coverage (RunSpecifiedTests, KJDEV)

**12/12 tests passing.** Per-class line coverage:

| Class | Coverage |
|---|---|
| LBRInteractionConvertSweeper | 100% |
| LBRInteractionCount (trigger) | 100% |
| LBRInteractionCountHandler | 100% |
| LBRInteractionReparentService | 98.7% |
| LeadConvertInvocable | 97.4% |

Scenarios covered: single re-parent, **bulk 200**, composite-dedup merge, conversion without Opportunity, C2I insert + skip-existing-pair, null/empty input, count maintenance (insert/delete/undelete), sweeper execute/start/finish/schedule, invocable hook.

> Note: because `Interaction_Code__c` is **globally unique**, two records can never share a code, so the spec's "dedup by Interaction_Code__c" branch is unreachable in practice — the composite (Type+Product+Date) path is the live dedup. The code branch is retained as defensive logic.

---

## 4. Baseline vs post-fix (Step 5, proven via anonymous Apex, rolled back)

```
VR (a) neither Contact nor Lead   -> BLOCKED (Contact_or_Lead_Required)
VR (b) both Contact and Lead      -> BLOCKED (Contact_or_Lead_Required)
VR (c) interaction on a converted Lead -> BLOCKED (Block_Converted_Lead)
BASELINE (standard Database.convertLead, no new automation):
    2/2 interactions still parented to the Lead, Contact null  -> defect reproduced
POST-FIX (LBRInteractionReparentService.reparent):
    2/2 interactions re-parented onto the Contact, Lead cleared
    2 Contact2Interaction__c rows created (Opportunity present)
```

This also confirms the standard convert button/path does **not** auto-reparent (there is no Lead trigger) — which is exactly why the daily **sweeper** exists alongside the guided invocable.

---

## 5. Production-decision items (NOT deployed to prod)

1. **MD→Lookup on `Contact__c` is irreversible-in-practice and changes the security model** (object gains its own OWD). In prod this must be a planned change with a maintenance window. Note: MD→Lookup **cannot be validated with a check-only/`--dry-run` deploy** — prod will need a real deploy (validate the rest separately).
2. **Roll-up removal in prod:** `Contact.Count_of_LBR_Interactions__c` (roll-up) must be deleted before the conversion; confirm nothing prod-only (reports, dashboards, list views, other rollups) depends on it. The replacement Number field is back-filled only as interactions change — a one-time backfill job may be wanted.
3. **OWD = Public Read/Write** was chosen to stay closest to today's effective visibility. Confirm against prod sharing policy; if tighter is required, add sharing rules.
4. **Lead Lightning pages:** the related list was added to `Lead-Lead Layout`. The org has 8 Lead record pages (`Lead_Record_Page`, `Lead_Record_PageALM`, `LeadPage`, etc.). Any page using the standard **Related Lists** component will surface it automatically; pages using individual "Related List – Single" components would each need one added. Confirm which page(s) are active per profile/app.
5. **Schedule the sweeper** in prod (e.g. `System.schedule('LBR Interaction Convert Sweeper','0 0 2 * * ?', new LBRInteractionConvertSweeper());`).
6. **VRs do not honor the org kill-switch** (`Application_Settings__c.Disable_Validation_Rules__c`). Existing org VRs do. Decide whether the two new VRs should also respect it for bulk data loads / integrations.
7. **Convert relies on managed packages** (DupeBlocker/AddressTools) that make callouts — they can block a convert at runtime; the invocable already surfaces that as a readable message, and the sweeper will retry on its next run.
```
