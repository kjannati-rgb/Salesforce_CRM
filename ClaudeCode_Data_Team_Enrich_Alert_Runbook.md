# Runbook: "Account is not complete" Data Team alert — dynamic fields + suppression

**Status: LIVE IN PRODUCTION 2026-08-16** (flow v33 Active). Built and verified in KJDEV
the same day. Supersedes `update-email-template-runbook.md`, whose Steps 1, 2 and 4 were
based on a mistaken reading of the trigger mechanism (see below).

## What the original runbook got wrong

| Original assumption | Actual |
|---|---|
| Legacy classic **Workflow Rule** fires the alert | **No rule exists.** The Email Alert is invoked as an `emailAlert` action from inside the `Opportunity` **master flow** (record-triggered, after-save) |
| Trigger object needs confirming via retrieve | Confirmed: **Opportunity, create-only** (`isNew_check`) |
| Recipients may be hardcoded emails | **Public group `Data_Team`** (`00G6g000000sPobEAE`) — 16 members, only 9 active |
| Build a **new** Flow, deactivate the old rule | No rule to deactivate. The branch already exists in the master flow, whose own description requires all after-insert/update logic to hang off that tree |
| Merge `{!MissingFieldsList}` into the template | **Impossible** — a classic Email Alert only accepts `SObjectRowId`; no per-record value can be passed in |

## Decisions taken

1. **Send mechanism** — replace the Email Alert with invocable Apex that renders the
   Classic template and substitutes a literal `[[MISSING_FIELDS]]` token. Keeps the
   Centellic HTML in the template (editable outside code) rather than in a flow text
   template.
2. **Suppression profiles** — `Custom: Data Management` **and** `System Administrator`.
3. **Whose creator** — the **Opportunity** creator, *not* the Account creator.

### Why not the Account creator

The original runbook copied the sibling `Account_New_Firm_Office_Data_Team` flow, which
suppresses on `Account.CreatedBy.Profile.Name`. That works there because the sibling
triggers on Account *create*, so the creator is the person who just acted. Here the
trigger is an Opportunity create, which can be years later. Production distribution of
the 420,725 accounts with an incomplete billing address:

| Account creator profile | Accounts |
|---|---|
| Custom: Data Management | 269,887 |
| System Administrator | 133,071 |
| Custom: Fin/Ops/HR | 12,769 |
| ALM - Custom: Sales Profile | 3,664 |
| Custom: Sales Profile | 1,237 |
| everything else | ~97 |

Suppressing on Account creator silences **95.8%** of cases — the bulk-migrated accounts
are both admin-created *and* the ones missing addresses. Suppressing on Opportunity
creator instead silences 605 of 894 opportunities created in the last year (**68%**),
leaving roughly 24 alerts a month.

Implemented as `$Profile.Name` (the running user) rather than
`$Record.CreatedBy.Profile.Name`: the branch is create-only, so the running user *is* the
Opportunity creator, and this avoids a four-level traversal. The same flow already uses
`$Profile.Name` for its Swoogo check.

## What was built

| Component | Change |
|---|---|
| `classes/DataTeamEnrichNotifier.cls` | **New.** Invocable: renders template against the Account, substitutes `[[MISSING_FIELDS]]`, resolves the group to **active** members, sends, logs failures to `Flow_Log__c` |
| `classes/DataTeamEnrichNotifierTest.cls` | **New.** 5 tests, 93% coverage |
| `email/unfiled$public/Data_Team_Enrich_Account.email` | **Updated.** Centellic HTML; Missing row now `[[MISSING_FIELDS]]`; intro no longer names all three fields |
| `flows/Opportunity.flow-meta.xml` | Action swapped `emailAlert` → `apex`; new formula `missing_fields_list`; two suppression conditions added to the `isMissing` rule |
| `workflows/Opportunity.workflow-meta.xml` | **Untouched** — the old Email Alert is left in place, now unreferenced, for rollback |

Two design details worth preserving:

- **Rendered against the Account, not the Opportunity.** The template merges only
  `{!Account.Name}`, `{!Account.Salesforce_Account_ID__c}` and `{!Account.Link}`. Passing
  `$Record.AccountId` as the whatId resolves all three directly.
- **Active-member resolution.** The `Data_Team` group holds 7 dormant members who were
  never removed. The old alert would have silently resumed mailing them the moment any
  were reactivated; the new code filters on `IsActive = true` at send time.

## KJDEV verification (done)

- Deploy succeeded; `Opportunity` flow **v29 Active**.
- `sf apex run test --tests DataTeamEnrichNotifierTest` → **5/5 pass, 93% coverage**.
- Read-only render check against a real KJDEV account with all three fields blank:
  - subject merged the account name;
  - `[[MISSING_FIELDS]]` survived the merge engine;
  - **no unresolved `{!` merge fields left** in the rendered body;
  - substituted row rendered as `Billing Country, Billing City, Billing Street`;
  - group resolved **11 members → 5 active**.

### Not yet verified
A live end-to-end send could not be exercised from the CLI: the deploying user is on
System Administrator, which the new suppression correctly blocks. To test the happy path,
create an Opportunity in KJDEV **as a user on a sales profile** against an account missing
exactly one billing field, and confirm the email names only that field. KJDEV emails are
`.invalid` for everyone except Kamyar, so a sandbox send reaches no one else.

## The local flow file was stale — do not deploy it

Deploying the repo's `Opportunity.flow-meta.xml` to production would have been
**destructive**. Diffed against a fresh PROD retrieve, the local copy was 78 lines short
and would have:

- **deleted** three live PROD elements: `Check_for_Swoogo_deal`,
  `Copy_1_of_Create_Schedules`, `Copy_2_of_Fault_notification_recipients`;
- **introduced** a `Renewal_Email_Alert` element and `EmailAlert_RenewalCreation` subflow
  that have never existed in production.

What was actually deployed is PROD-retrieved-plus-three-changes, verified by diffing the
merged file against a *second* pristine retrieve — the only differences were the action
swap, the two suppression conditions and the `missing_fields_list` formula. That artifact
is kept at `prod-deploy/data-team-enrich/`.

`Renewal_Email_Alert` was deliberately **excluded**. It remains in the repo copy and is
still undeployed. **The repo's `flows/Opportunity.flow-meta.xml` is now known-stale
against production** — always retrieve fresh before touching that flow again.

## Production deploy (completed 2026-08-16)

Order matters and is not the obvious one. Activating the flow *before* deploying the
template is safe (the new Apex renders the old template, finds no token, sends today's
static wording). The reverse order puts a literal `[[MISSING_FIELDS]]` in real emails,
because the old active version would render the new token-bearing template.

1. **Apex first** — `DataTeamEnrichNotifier` + test. Inert until the flow points at it.
   5/5 tests. `NoTestRun` is rejected in production; use
   `--test-level RunSpecifiedTests --tests DataTeamEnrichNotifierTest`.
2. **Flow** — deployed as **Draft v33** (org has "deploy flows as active" OFF).
3. **Activate** — `FlowDefinition` with `activeVersionNumber=33`. v33 Active, v32 Obsolete.
4. **Template last** — token-bearing HTML.

Post-deploy verification (read-only render against a real incomplete PROD account, no
send): subject merged, `[[MISSING_FIELDS]]` survived the merge engine, **no unresolved
`{!` merge fields**, substituted row correct, group resolved **16 members → 9 active**,
matching the original alert's recipient list exactly.

**Rollback:** revert the flow to v32, which restores the `emailAlert` action. The old
Email Alert is deliberately left in `Opportunity.workflow-meta.xml`, now unreferenced.

**Re-run the test class standalone** — `EmailTemplate` is a setup object in this org, and
the `MIXED_DML_OPERATION` failure it causes did **not** surface in a deploy-time
`RunSpecifiedTests` run (which reported 5/5 green) but did on a standalone
`sf apex run test`.

## Integration test (KJDEV, 5/5 passing)

`DataTeamEnrichAlertFlowTest` closes the gap that CLI testing could not: it drives the
whole path through the master flow rather than calling the Apex directly, using
`System.runAs` to create the Opportunity as users on different profiles.

| Case | Creator profile | Account | Expected |
|---|---|---|---|
| `alertFiresForSalesUserWithSingleMissingField` | Custom: Sales Profile | only Billing City blank | email sent |
| `alertFiresWhenAllThreeMissing` | Custom: Sales Profile | all three blank | email sent |
| `noAlertWhenAddressComplete` | Custom: Sales Profile | complete | no email |
| `suppressedForSystemAdministratorCreator` | System Administrator | all three blank | no email |
| `suppressedForDataManagementCreator` | Custom: Data Management | all three blank | no email |

Assertions compare `Limits.getEmailInvocations()` either side of the insert. The negatives
are only meaningful because the positives pass — each negative changes exactly one variable
(address, or profile) against a passing positive, so a zero increment is attributable
rather than the flow simply never having run.

Two traps this test had to work around, both of which make a test pass for the wrong reason:

- `TestDataFactory.bypassAutomation()` **cannot be used** — it inserts a fresh org-level
  `Application_Settings__c`, which collides under `SeeAllData` with the real one
  (`DUPLICATE_VALUE` on `SetupOwnerId`). The local helper reuses the existing row.
- The helper forces `Disable_Process_Builders__c` **off**. That is the flag the master
  flow's own `CheckAutomationDisabled` formula reads — inheriting a `true` from the org
  would disable the flow under test and every assertion would pass vacuously.

`SeeAllData=true` is required because the flow hardcodes the `Data_Team_Enrich_Account`
template and `Data_Team` group, which a test cannot create. The email assertions therefore
double as a check that both still exist and are reachable.

**Not deployed to production.** A `SeeAllData` test that inserts an Opportunity drags in the
org's full automation; if it proves flaky in production it would block unrelated deploys,
and this org already carries pre-existing red tests. Worth deploying only if you want the
regression protection there and are willing to watch it for a few deploys.

## Still unverified

Nobody has **looked at the rendered email**. The render is verified structurally in both
orgs, but the visual result — Centellic layout, the dynamic row, the button link — has not
been seen. Quickest check is Setup → **Log in as** a sales user in KJDEV and create an
Opportunity on an account missing one field; KJDEV emails are `.invalid` for everyone
except Kamyar, so only his inbox receives it.

## Open question

Deactivating the 7 dormant `Data_Team` group members is now cosmetic rather than a
correctness issue — the Apex filters them out. Worth tidying the group membership
separately if the Data team wants an accurate distribution list.
