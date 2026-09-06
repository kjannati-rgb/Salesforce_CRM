# REV-68 — Production deployment runbook (LBR_PROD)

Deploy target: `LBR_PROD` (`kamyar.jannati@lbresearch.com`, Org `00D6g0000081IOg`, **production**).
Source: the `force-app` tree in this repo (already built & verified in KJDEV).

**Verified prod facts (read-only audit, 2026-06-11):** single Master-Detail (`Contact__c`); no Contract field; exactly one roll-up over interactions (`Count_of_LBR_Interactions__c`); 29,973 interaction records, max 5 per Contact; 0 records with Contact null. Prod matches the sandbox.

> ⚠️ The **MD→Lookup conversion (Step 3) is the one irreversible, security-changing step** and **cannot be `--dry-run` validated**. Run it in a maintenance window. Everything else is additive/standard.

---

## 0. Pre-flight (re-run at deploy time — all read-only)

```bash
# Confirm target is production
sf data query -o LBR_PROD -q "SELECT Name, IsSandbox FROM Organization"
# Re-confirm the roll-up inventory hasn't changed (expect exactly ONE)
sf data query --use-tooling-api -o LBR_PROD -q "SELECT EntityDefinition.QualifiedApiName, QualifiedApiName, DataType FROM FieldDefinition WHERE DataType LIKE '%Roll-Up%'"  # grep for Interaction
# Snapshot the count so backfill can be validated later
sf data query -o LBR_PROD -q "SELECT COUNT() FROM LBR_Interactions__c"
```
- [ ] Production confirmed, exactly one interaction roll-up, volume ~30k.
- [ ] Maintenance window booked; notify that interaction **sharing changes to Public Read/Write** and records gain an Owner.
- [ ] Stakeholders confirm nothing prod-only (reports/dashboards/list views) hard-depends on the roll-up field beyond a recomputable count.

## 1. Sandbox-vs-prod metadata diff (safety)

```bash
# Optional but recommended: retrieve the prod versions of touched components into a scratch dir and diff,
# so prod-only customizations on these layouts/object aren't overwritten.
sf project retrieve start -m "Layout:Lead-Lead Layout" -m "Layout:LBR_Interactions__c-LBR Interactions Layout" -o LBR_PROD --target-metadata-dir ./_prod_compare
```
- [ ] Reconcile any prod-only layout sections before deploying layouts (Step 6).

## 2. Remove the blocking roll-up  *(destructive, reversible by re-creating)*

```bash
sf project deploy start --manifest rev68-manifest/empty-package.xml \
  --post-destructive-changes rev68-manifest/destructiveChangesPost.xml -o LBR_PROD --dry-run   # validate first
sf project deploy start --manifest rev68-manifest/empty-package.xml \
  --post-destructive-changes rev68-manifest/destructiveChangesPost.xml -o LBR_PROD             # real
```
- [ ] Roll-up `Contact.Count_of_LBR_Interactions__c` removed. (Underlying interactions untouched.)

## 3. Schema conversion  *(REAL only — no dry-run; the irreversible step)*

Deploys: `Contact__c` MD→Lookup, OWD→Public Read/Write, new `Lead__c` + `Interaction_Code__c`, both VRs, and the replacement `Contact.Count_of_LBR_Interactions__c` Number field.

```bash
sf project deploy start -m "CustomObject:LBR_Interactions__c" \
  -m "CustomField:Contact.Count_of_LBR_Interactions__c" -o LBR_PROD
```
- [ ] Deploy succeeded; `Contact__c` is now Lookup; `Lead__c`, `Interaction_Code__c`, VRs present.
- [ ] Quick check: `sf data query -o LBR_PROD -q "SELECT COUNT() FROM LBR_Interactions__c WHERE Contact__c != null"` still ≈ 29,973 (no record loss).

## 4. Permission set  *(after the object is standalone)*

```bash
sf project deploy start -m "PermissionSet:LBR_Interactions_on_Leads" -o LBR_PROD
```
- [ ] Assign to the relevant users / permission-set group per your access model (not only the deployer):
  `sf org assign permset -n LBR_Interactions_on_Leads -o LBR_PROD -b "<user-or-list>"`

## 5. Apex  *(RunSpecifiedTests — prod has pre-existing unrelated red tests, so do NOT use RunLocalTests)*

```bash
sf project deploy start \
  -m "ApexClass:LBRInteractionReparentService" -m "ApexClass:LBRInteractionConvertSweeper" \
  -m "ApexClass:LBRInteractionCountHandler" -m "ApexClass:LeadConvertInvocable" \
  -m "ApexTrigger:LBRInteractionCount" \
  -m "ApexClass:LBRInteractionReparentService_Test" -m "ApexClass:LBRInteractionCount_Test" \
  -m "ApexClass:LBRInteractionConvertSweeper_Test" -m "ApexClass:LeadConvertInvocableReparent_Test" \
  -o LBR_PROD -l RunSpecifiedTests \
  -t LBRInteractionReparentService_Test -t LBRInteractionCount_Test \
  -t LBRInteractionConvertSweeper_Test -t LeadConvertInvocableReparent_Test -t LeadConvertInvocable_Test
```
- [ ] 12 tests green; org-wide coverage stays ≥75% (these classes are 97–100%).

## 6. Layouts / Lightning pages

```bash
sf project deploy start -m "Layout:LBR_Interactions__c-LBR Interactions Layout" \
  -m "Layout:Lead-Lead Layout" -o LBR_PROD
```
- [ ] Confirm which of prod's **8 Lead record pages** are active per profile/app. Any page using the standard **Related Lists** component surfaces the new list automatically; pages using individual "Related List – Single" components each need one added (manual, per page).

## 7. Post-deploy activation

- [ ] **Schedule the sweeper** (Apex Scheduler or anonymous):
  `System.schedule('LBR Interaction Convert Sweeper','0 0 2 * * ?', new LBRInteractionConvertSweeper());`
- [ ] **Backfill the count field** (it only updates as interactions change). Safest is a one-off batch that recomputes per Contact (re-uses `LBRInteractionCountHandler` logic). ~30k rows / max 5 per Contact → trivial. *(I can provide a `LBRInteractionCountBackfill` batch + test if you want it.)*
- [ ] Smoke test: create a Lead, add an interaction to it, convert via the guided flow → interaction re-parents to the Contact; run the sweeper once to confirm it catches a standard-convert orphan.

## 8. Rollback notes

- Steps 2 & 3 are the sensitive ones. The interaction **records are never deleted**, so "rollback" means re-converting Lookup→Master-Detail and re-creating the roll-up — possible but disruptive (Lookup→MD requires every record to have a parent; all 29,973 do today). Treat Step 3 as forward-only and rely on the maintenance window + pre-flight rather than rollback.
- Steps 4–7 are independently reversible (delete perm set / revert Apex / revert layouts).

---

### Component inventory (what ships)
- **Destructive:** `Contact.Count_of_LBR_Interactions__c` (roll-up).
- **Schema:** `LBR_Interactions__c` (Contact__c→Lookup, OWD, +Lead__c, +Interaction_Code__c, +2 VRs); `Contact.Count_of_LBR_Interactions__c` (Number).
- **Security:** perm set `LBR_Interactions_on_Leads`.
- **Apex:** `LBRInteractionReparentService`, `LBRInteractionConvertSweeper`, `LBRInteractionCountHandler`, `LeadConvertInvocable` (modified), trigger `LBRInteractionCount` + 4 test classes.
- **UI:** LBR Interactions layout, Lead Layout related list.
