# Runbook: "Account is not complete" Data Team alert — dynamic fields + suppression

**Status:** Built and verified in KJDEV 2026-08-16. **Not deployed to production.**
Supersedes `update-email-template-runbook.md`, whose Steps 1, 2 and 4 were based on a
mistaken reading of the trigger mechanism (see below).

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

## Production deploy

1. Deploy the four components above with
   `--test-level RunSpecifiedTests --tests DataTeamEnrichNotifierTest`.
2. **Flows deploy as Draft in PROD** (the org has "deploy flows as active" OFF). Activate
   the new `Opportunity` flow version via `FlowDefinition` after deploy, and confirm the
   previously active version goes Obsolete — a period with *no* active master flow would
   disable far more than this alert.
3. Confirm `Data_Team_Enrich_Account` in PROD still contains the `[[MISSING_FIELDS]]`
   token after deploy. If the token is missing the email will read "Not specified" rather
   than failing, so this will not announce itself.
4. Burn-in: leave the old Email Alert in the workflow metadata. Rollback is reverting the
   flow to the prior version, which restores the `emailAlert` action.

**Re-run the test class standalone after deploying** — `EmailTemplate` is a setup object
in this org, and the `MIXED_DML_OPERATION` failure it causes did **not** surface in the
deploy-time `RunSpecifiedTests` run (which reported 5/5 green) but did on a standalone
`sf apex run test`.

## Open question

Deactivating the 7 dormant `Data_Team` group members is now cosmetic rather than a
correctness issue — the Apex filters them out. Worth tidying the group membership
separately if the Data team wants an accurate distribution list.
