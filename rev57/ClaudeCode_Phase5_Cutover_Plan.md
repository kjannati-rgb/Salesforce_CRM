# REV-57 — Production Cutover Plan & Deployment Manifest

**Date:** 2026-06-10 · **Source:** KJDEV (built + tested) · **Target:** `LBR_PROD` · **Status:** PLAN — no prod changes yet, needs Kam sign-off.
Manifest file: [`rev57_package.xml`](rev57_package.xml).

> Golden rule recap: `LBR_PROD` deploys flows as **Draft** (org setting), so every flow must be **activated via FlowDefinition** after deploy. Production is otherwise retrieve-only until this sign-off.

---

## 0. What ships (manifest summary)

| Type | Components |
|---|---|
| **CustomObject** (CMDT) | `PFC_Task_Mapping__mdt`, `PFC_Campaign_Mapping__mdt` |
| **CustomField** | PFC: `Product_Brand__c`, `PFC_Source__c`, `Related_Form_Completion__c` · 11 fields on PFC_Task_Mapping · 3 on PFC_Campaign_Mapping |
| **CustomMetadata** (records) | 4 × PFC_Task_Mapping (Newsfeed, Inbound Form, Scored Lead, Event Sponsorship) · 6 × PFC_Campaign_Mapping (Lexology-PRO forms) |
| **Flow** (deploy Draft → activate) | NEW: `Pardot_Create_PFC_Orchestrator`, `PFC_Check_And_Link`, `PFC_Relink_Lead_to_Contact_on_Conversion`, `PFC_Log_Fault`, `PFC_Add_Campaign_Member` · MODIFIED: `On_Pardot_Form_Creation` |
| **PathAssistant** | `Pardot_Form_Completion_Newsfeed`, `PFC_Marketing_Services` |
| **PermissionSet** | `PFC_REV57_Field_Access` (FLS for the 3 new fields) |
| **CompactLayout** | `Newsfeed_Compact` |
| **Layout** | `Pardot Form Completion Layout` (added fields + Linked Form Completions related list) |
| **FlexiPage** | `Pardot_Form_Completion_Record_Pagev2` (3 fields + Linked Form Completions related list) |

**Deliberately NOT in the package** (handled manually — see §3): the `Newsfeed_Subscribers` **RecordType** (deploying it would overwrite prod's picklist-value assignments), the **Campaign + "Registered" status** (data, not metadata), and the **Lightning page → record-type activation** (App Builder only).

---

## 1. Pre-flight (do first)

1. `sf org display --target-org LBR_PROD` — confirm the right org.
2. **Backup / snapshot the components we change**, so rollback is trivial:
   ```
   sf project retrieve start --target-org LBR_PROD --output-dir rev57/prod_backup \
     --metadata "Flow:Create_Pardot_Form_from_Task" "Flow:On_Pardot_Form_Creation" \
     "FlexiPage:Pardot_Form_Completion_Record_Pagev2" \
     "Layout:Pardot_Form_Completion__c-Pardot Form Completion Layout" \
     "CustomObject:Pardot_Form_Completion__c"
   ```
3. **Confirm prod data the config depends on:**
   - Campaign **"Lexology - LeadGen Form - ROI Campaign"** exists & unique (✅ verified 2026-06-10 — the inbound mapping resolves by this name).
   - The `Newsfeed_Subscribers` RT exists (✅ Id `012Px000003AadBIAS`).
4. **Validate-only deploy** (no changes): `sf project deploy start --target-org LBR_PROD --manifest rev57/rev57_package.xml --dry-run --test-level RunLocalTests` — confirm 0 errors. (Prod has pre-existing red tests; if RunLocalTests is blocked, use `--dry-run` without tests, since this change set has no Apex.)

## 2. Deploy metadata (single window)

```
sf project deploy start --target-org LBR_PROD --manifest rev57/rev57_package.xml
```
All flows land **Draft/Inactive** — expected. Nothing is live yet (orchestrator inactive = no behaviour change). Safe to deploy ahead of the cutover moment.

## 3. Manual / data steps (can't deploy)

1. **Create the campaign + member status** (run the verified apex `rev57/create_nf_campaign.apex` adapted for prod, or by hand):
   - Campaign **"Lexology - Free Newsfeed Subscribers"** (Type `Other` to avoid the "Event Location" VR), Active.
   - Add CampaignMemberStatus **"Registered"** (HasResponded = true).
   - ⚠️ The name must exactly match the CMDT `Default_Campaign_Name__c` value, or the lookup won't resolve.
2. **Compact layout → Newsfeed RT assignment:** Setup → Object Manager → Pardot Form Completion → **Compact Layouts → Compact Layout Assignment** → set `Newsfeed_Compact` for the **Newsfeed Subscribers** record type. *(Done manually to avoid deploying the whole RecordType and clobbering prod picklist-value assignments.)*
3. **PathAssistant** ships in the package — no manual step, but confirm the **Newsfeed** + **Marketing Services** paths show as Active afterwards.

## 4. Activation (the cutover moment — low-volume window)

Activate the new flows and flip the old one **together** to avoid a gap where inbound PFCs are double-created or missed (flow 1 and the orchestrator both fire on `PFC:`/`Lead scoring MQL`/`EVT` task creation).

1. **Activate** (FlowDefinition `activeVersionNumber` = the deployed version, or via UI Activate): `Pardot_Create_PFC_Orchestrator`, `PFC_Check_And_Link`, `PFC_Relink_Lead_to_Contact_on_Conversion`, `PFC_Log_Fault`, `PFC_Add_Campaign_Member`, and the new version of `On_Pardot_Form_Creation`.
2. **Deactivate** `Create_Pardot_Form_from_Task` (FlowDefinition `activeVersionNumber` = 0) — **in the same deployment** as step 1 so the swap is atomic. Example FlowDefinition deploy bundles both.
3. **Assign permission set** `PFC_REV57_Field_Access` to the relevant profiles/users (so reps/reports can see the 3 new fields; flows run in system context and don't need it).
4. **App Builder activation:** open `Pardot Form Completion Record Pagev2` → **Activation** → set Org Default (+ App Default for Sales) and **Assign by Record Type** → tick **Newsfeed Subscribers** (and confirm the other RTs). *(Cannot be deployed.)*

## 5. Pardot / marketing side (your team)

- Build the **`NF - ` Task** completion action in Pardot/MCAE, subject exactly `NF - [First/Last] - Lexology - Free Newsfeed Subscriber - [Month/Year]`, with the **Task WhoId** set to the Lead/Contact. Confirm the prefix is `NF - ` (left-anchored) — the orchestrator keys on it.
- Until this is live, the SF side is dormant for newsfeed (no NF tasks = no newsfeed PFCs); inbound/MQL/EVT continue normally via the orchestrator.

## 6. Smoke tests (prod, right after cutover)

1. **Inbound regression:** create one `PFC:` task (or wait for a real one) → confirm a Form Completion PFC is created, field-for-field as before, Lead/Contact linked, Name/Campaign stamped.
2. **Newsfeed:** once Pardot is live (or a manual `NF -` task) → Newsfeed PFC created, Source=Newsfeed, Brand=Lexology, Name `… | Lexology Newsfeed Subscriber - <Month Year> - MQL`, Campaign + **Registered** CampaignMember created, Path visible.
3. **Cross-link:** a person with an open inbound + a newsfeed → linked both ways.
4. **Conversion relink:** convert a lead with an open PFC → PFC moves to Contact.
5. Check `Flow_Log__c` for any fault rows.

## 7. Rollback (fast, clean)

The build is **additive** — fields/CMDTs/flows/pages can stay inert. To revert behaviour:
1. **Re-activate** `Create_Pardot_Form_from_Task` (FlowDefinition activeVersionNumber = prior version).
2. **Deactivate** `Pardot_Create_PFC_Orchestrator`, `PFC_Check_And_Link`, `PFC_Add_Campaign_Member`, `PFC_Relink_Lead_to_Contact_on_Conversion` (FlowDefinition = 0).
3. Re-deploy the **backed-up** `On_Pardot_Form_Creation` (restores the prior campaign formula) if needed.
New fields/pages/list views can remain (harmless). No data cleanup required (newsfeed PFCs already created stay valid).

## 8. Open decisions to confirm before go-live

- **Async path:** the orchestrator runs synchronously (no +1-min scheduled path). Bulk-200 passed in test. Decide whether to add flow 1's old `+1 min / batch 50` scheduled path for month-end surge smoothing, or monitor first. *(Recommend: monitor; add only if limits appear.)*
- **Campaign membership scope:** confirmed to apply to inbound mapped forms too (not just newsfeed).
- **Deferred fast-follows** (separate tickets): email-fallback person matching; Apex+tests for cross-linking; null-RT backfill of 47k legacy records (D4).

## 9. Post-go-live
- Update REV-57 in Jira with final design + ACs; attach the KJDEV test evidence (Phase 4 10/10, campaign membership, relink, naming).
- Raise the deferred-item tickets above.
