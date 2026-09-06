# Topic: Opportunity Stages & Closing

**Status:** draft — pre-build definition per Standard v2 §7 (items 2, 4, 5)
**Owner:** Kamyar Jannati (Head Data and CRM)
**Baseline (DoD #5):** 629 CRM Support cases in trailing 12 months (2025-07-04 → 2026-07-04) whose Subject matches the stage/close/approval cluster (LIKE terms: stage, close, won, approv, unlock, reopen, uplift — recorded 2026-07-04; keyword-subject method, refresh at quarterly review).

## Classification description (for topic routing)

> Questions about Salesforce **Opportunity stages and closing**: what the stages are and when to use them, why a stage change or save is blocked by an error, how to close an opportunity as won or lost, the Closed Won approval route, cancellation opportunities, and why closed opportunities are locked or need reopening. Covers error messages raised while changing Opportunity stage or saving an Opportunity.

### Explicitly OUT of scope (route elsewhere / fallback intake)

Mutual-exclusivity notes for future topic descriptions — these are adjacent and must never be claimed by this topic:

- **Quote errors and quote approvals** (except where the error blocks an Opportunity stage change — the renewal-uplift quote errors are answered here because users experience them while processing renewals).
- **Deleting, merging, or de-duplicating opportunities.**
- **Opportunity ownership changes and Opportunity Team permissions** (the topic explains that owner change is admin-only, then hands off to intake).
- **Forecasting tools (Clari) and dashboards.**
- **Login/SSO** (own topic per Standard §6).
- Anything not covered by the three grounding articles — the topic must say so and offer a case, never improvise.

## Grounding Knowledge (DoD #1)

- `knowledge/opportunity-stages/kb-opp-stage-model.md`
- `knowledge/opportunity-stages/kb-opp-closing-and-approval.md`
- `knowledge/opportunity-stages/kb-opp-stage-errors.md`

All three verified against PROD metadata 2026-07-04 (see `ClaudeCode_AgentTopic_OppStages_Phase0_Grounding.md`).

## Topic instruction constraints (to carry into the build)

1. Answer **only** from the grounding articles. If the question or error is not in them, say you don't have that information and offer to create a case. Never describe org behaviour from general Salesforce knowledge.
2. When escalating, create the case with: exact error text, Opportunity ID/link, what the user was changing, and the business reason. Case must carry the agent origin marker.
3. Requests to *change data* (reopen/unlock a closed opp, move a stage on the user's behalf, edit a closed record) are **not actions this topic performs** in v1 — explain the why from the articles, then create a structured case for the CRM team.
4. Never suggest bypasses (`Application_Settings__c`, bypass permissions) as user remedies; those are admin mechanisms. The articles mention them only as "raise a case" paths.

## Test set

`utterance-corpus.yaml` in this folder — 18 in-scope utterances (from real case subjects, scrubbed per Standard §2), 3 invention-bait traps, 5 out-of-scope routing checks. Gate: ≥95% routing over the whole corpus, 100% grounding fidelity, all traps produce "don't have that → case".
