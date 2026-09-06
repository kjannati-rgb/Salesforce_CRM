# Agent Promotion Runbook — Centellic CRM Support

Companion to `ClaudeCode_WorldClass_Agent_Standard_v2.md` (§5, §7). This is the concrete KJDEV → LBR_PROD path for one topic (or one change to an existing topic). It exists because three org realities break the naive "commit → deploy" mental model:

1. **Knowledge articles are records, not metadata** — they don't deploy via `sf project deploy`; they need a separate load step.
2. **KJDEV holds no production data** — routing tests run dry, but action tests need seeded records.
3. **LBR_PROD deploys flows as Draft** — the org's "deploy flows as active" setting is OFF; every flow arrives inactive and must be activated post-deploy.

Session prerequisite for all CLI steps: clear the dead proxy env vars first (`HTTP_PROXY`/`HTTPS_PROXY`), or `sf` commands hang / exit 13. Org aliases: `KJDEV` (sandbox), `LBR_PROD` (production).

---

## What lives where

| Artifact | Form | Promotion path |
|---|---|---|
| Topics, instructions, actions (GenAi* metadata) | Metadata XML in `force-app/` | `sf project deploy` |
| Action flows | Flow metadata in `force-app/` | `sf project deploy` + **manual activation in PROD** |
| Action Apex + tests | Classes in `force-app/` | `sf project deploy` (RunSpecifiedTests — prod has pre-existing red tests, never RunLocalTests) |
| Knowledge article content | Markdown files in repo (`knowledge/` per topic), frontmatter: owner, review date, verified-against sources | Load script (API) → Knowledge, per org |
| Utterance corpus / test specs | AiEvaluationDefinition YAML + scrubbed utterances in repo | `sf project deploy`, run in Testing Center |
| KJDEV seed data scripts | Scripts in repo alongside topic | Run in KJDEV only — never in PROD |
| Kill-switch settings | `Application_Settings__c` records | Created once per org, verified per topic |

## Phase 0 — Author (repo, no org yet)

1. Retrieve the metadata the topic's answers depend on (`sf project retrieve start` from **PROD** — KJDEV can drift; grounding truth is production behaviour).
2. Author/update the Knowledge article Markdown from that retrieved metadata. Fill frontmatter: owner, review date, list of metadata files verified against. No placeholders.
3. Author topic + instructions + actions; author/extend the utterance test spec (min. 15 real utterances + 3 invention-bait traps). **Scrub utterances before commit** — replace real names/emails/accounts with synthetic equivalents that keep the phrasing shape.
4. Branch per feature, commit everything above together. The PR is the review gate: article content review + fallback-topic-description re-review + DPO check (if personal data) happen here.

## Phase 1 — KJDEV validation

5. Deploy metadata to KJDEV: `sf project deploy start -o KJDEV` (scoped to the topic's components).
6. Load article content to KJDEV Knowledge via the load script; publish.
7. **Seed action-path data** — run the topic's seed script against KJDEV. Verify any external dependency is alive first (e.g. the CPQ calc-service auth in KJDEV has been known to expire, which silently blocks anything quote-shaped — check before blaming your build).
8. Activate the topic's flows in KJDEV if they arrived Draft (sandbox setting may differ from prod — verify, don't assume).
9. Run the full utterance corpus in Testing Center (`sf agent test run`), not just the new topic's slice — a new topic can steal routes from existing ones. Gate: ≥95% routing on the whole corpus, 100% grounding fidelity on the new topic, all traps escalate cleanly.
10. Kill-switch drill: flip the topic's `Application_Settings__c` bypass, confirm actions go inert while the agent stays up, flip back.
11. Record the topic's baseline: trailing-12-month case volume for its cluster, written into the topic's doc/Confluence page before promotion.

## Phase 2 — PROD promotion

Do these in order; the ordering is load-bearing.

12. Deploy metadata: `sf project deploy start -o LBR_PROD` with `--test-level RunSpecifiedTests --tests <topic's test classes>`. Validate-only first (`--dry-run`) if the changeset is large.
13. Load article content to PROD Knowledge via the load script; publish. **Articles before activation** — an active topic with missing Knowledge invents or escalates everything.
14. **Activate the flows.** They arrived as Draft. Activate via FlowDefinition metadata or Setup, then *verify* each shows Active — do not take the deploy's success as activation. (SetupAuditTrail is a reliable post-deploy verification source when SOQL views lag.)
15. Verify agent permissions: the agent user's permission set covers exactly the new topic's objects/fields/Apex classes — remember missing `classAccesses` fails *silently* (blank responses, no error), so check the permset explicitly rather than waiting for symptoms.
16. Activate/publish the new agent version with the topic enabled.
17. Smoke test in production: 3–5 utterances from the corpus (happy path, one trap, one action with confirmation gate). Confirm the case origin marker lands on any created case.
18. Confirm KPI reporting picks the topic up (deflection report, escalation-quality report).

## Phase 3 — Post-promotion

19. Log the promotion on the topic's Confluence page (CRMS space, "REV-XX — Feature: Solution Design & Runbook" convention): date, deploy IDs, flow versions activated, article versions loaded, baseline number.
20. Enter the weekly review cadence (first 8 weeks) per Standard §5.

## Rollback

- **Behaviour problem (wrong answers, bad routing):** flip the topic's `Application_Settings__c` bypass (actions inert) or disable the topic on the agent — both are no-deploy, minutes not hours.
- **Whole-agent problem:** deactivate the agent from Setup.
- **Bad article:** fix the Markdown in repo, re-run the load script; for immediate mitigation, archive the article in PROD (record operation, no deploy) — but the repo fix must follow the same day or the repo stops being canonical.
- **Bad flow version:** deactivate the flow (reverts to prior active version if one exists) — again no deploy.

Never hand-edit topic instructions or article text directly in PROD as the *fix* — mitigation is allowed (archive/deactivate), correction goes through the repo.
