# Production deployment runbook — Opportunity Team add/remove flow

Two independent, sequenced deliverables. **Do not run anything against production without explicit sign-off.**
Replace `PROD` below with your production org alias (none is configured in this workspace yet — add one with `sf org login web --alias PROD`).

---

## Stage 1 — Hotfix (low risk, ship first)

Deploys the patched team flow as a new Active version (production equivalent of sandbox V22).
**Drop-in:** same API name `Create_Opportunity_Contacts`, same `recordid` page wiring — no record-page change needed.

**What it fixes:** fault handling on every DML/Get (was none), `SystemModeWithSharing` (was WithoutSharing),
CS-Contact trailing-`;` trim, relative renewal URL, dead-resource removal.

```sh
# 1. Validate only (no save) + run local tests
sf project deploy start --manifest scripts/deploy/manifest-v22-hotfix.xml --dry-run --test-level RunLocalTests --target-org PROD

# 2. Deploy for real (creates new Active version; prior version -> Obsolete)
sf project deploy start --manifest scripts/deploy/manifest-v22-hotfix.xml --target-org PROD
```

**Rollback:** Setup -> Flows -> open the flow -> activate the prior version. (Flow versions are retained; nothing is destroyed.)

---

## Stage 2 — Rebuild rollout (after Stage 1 + sandbox UAT)

Deploys the from-scratch flow `Opportunity_Team_Member_Manager` and the 6 Opportunity record pages that
embed it as a second widget (additive — the existing widget stays).

**What it adds over the hotfix:** explicit duplicate-member guard (this org does NOT block duplicate
OpportunityTeamMember inserts at the platform level — verified), owner-as-member guard, self-removal
confirmation, Id-based Opportunity updates, role-name constants, full descriptions.

> ⚠️ **PROD has "Deploy processes and flows as active" OFF** — a deployed flow lands as **Draft** even if its
> metadata says Active. Deploy + activate the flow BEFORE pointing the pages at it, or the widget breaks.
> Deploy order: (1) flow, (2) activate via FlowDefinition, (3) pages.

```sh
# 1. Deploy the flow (lands as Draft in prod)
sf project deploy start --metadata Flow:Opportunity_Team_Member_Manager --target-org PROD

# 2. Activate it (FlowDefinition with the deployed version number)
sf project deploy start --metadata FlowDefinition:Opportunity_Team_Member_Manager --target-org PROD
#    verify: sf data query --use-tooling-api --target-org PROD \
#      -q "SELECT VersionNumber, Status FROM Flow WHERE Definition.DeveloperName='Opportunity_Team_Member_Manager'"

# 3. Point the record pages at it (cutover) — deploy the 6 swapped FlexiPages
sf project deploy start --manifest scripts/deploy/manifest-rebuild-rollout.xml --target-org PROD
```

**Pilot before full rollout:** the widget visibility rule is `User.Division` OR record owner OR
`User.Can_Add_Remove_Opp_Team_Member__c`. Grant the custom flag to a small pilot group, validate, then
broaden. No further metadata change is needed to pilot.

**Cutover:** once the rebuild is trusted, remove the old `Create_Opportunity_Contacts` widget block from the
6 flexipages (and optionally deactivate the old flow). Keep the old flow version around as rollback for one cycle.

**Rollback:** redeploy the previous flexipage versions (or remove the `*_rebuild` componentInstance blocks) and
deactivate the new flow. The old widget continues to work throughout — that's why this rollout is additive.

---

## Pre-flight dependency check (all already present in prod, since V21 uses them)

- Subflow `Flow_log_v3`
- Managed component `adminshelper:fabullousConfettiFlowComponent`
- Standard components `flowruntime:lookup`, `flowruntime:datatable`
- Fields: `Opportunity.CS_Contact__c`, `Client_Engagement_Director__c`, `Sales_Development_Representative__c`,
  `Previous_Opportunity__c`; `OpportunityTeamMember` standard fields
- Visibility-rule fields: `User.Can_Add_Remove_Opp_Team_Member__c`, `Opportunity.Record_Owner_Running_User__c`

## Known follow-up (not part of this rollout)

- `Opportunity.CS_Contact__c` is an unrestricted multi-select picklist storing person names -> value sprawl.
  Re-platform it to a proper field type (text/long-text or a related list) in a separate, sequenced change.
- Optional hardening: replace the `$Profile.Name != 'System Administrator'` closed-won bypass with a custom permission.
