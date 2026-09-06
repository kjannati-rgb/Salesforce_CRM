# World-Class Agent Standard v2 — Centellic CRM Support

Every topic must pass this bar before promotion to production. This is the difference between a demo and an operating capability.

**v2 changes (2026-07-04):** each edit against v1 is tagged **[NEW]** or **[CHANGED]** with a rationale. Unmarked text is unchanged from v1. Changes resolve four collisions with known org realities (Knowledge articles are records not metadata; KJDEV holds no data; LBR_PROD deploys flows as Draft; PII in the utterance corpus) and add two missing controls (kill switch; stale-article enforcement).

---

## 1. Grounding fidelity — zero invented facts

- Every claim the agent makes about org behaviour (rules, stages, approval chains, field requirements) traces to grounded Knowledge that was itself derived from **retrieved metadata**, not memory or generic Salesforce documentation.
- Standing rule: **metadata → article → agent.** No article ships with unverified placeholders; the Claude Code retrieve-and-verify pass is a mandatory step in authoring, not an optional one.
- Topic instructions explicitly forbid answering outside the grounded Knowledge, and the test set includes trap questions designed to bait invention (e.g. asking about a stage or rule that doesn't exist). Expected behaviour: "I don't have that — let me create a case."
- Knowledge has an owner and a review date. An article older than its review date is treated as stale and flagged.
- **[NEW] Staleness is enforced by a mechanism, not a habit.** A scheduled flow (or standing report subscription) surfaces every article past its review date to its owner monthly. "Treated as stale and flagged" without a named mechanism is an aspiration, not a control. The flow/report is part of the platform build, shipped before the first topic.
- **[NEW] Article source of truth lives in the repo.** Salesforce Knowledge articles are *records*, not metadata — they cannot ride the CLI deploy pipeline. Each article is authored as a Markdown file in source control (one file per article, frontmatter carrying owner, review date, and the metadata sources it was verified against). A load script (Bulk/REST API) publishes repo content to Knowledge in each org; the repo file is canonical and hand-edits to the article record in production are treated the same as hand-edits to metadata — forbidden. This closes the gap where §5's "no hand-editing in production" was unenforceable for the one artifact grounding fidelity depends on.

## 2. Routing precision

- Topic classification descriptions are mutually exclusive by design; every new topic is checked against all existing descriptions for overlap **before** it is added.
- A standing utterance corpus (drawn from real case subjects, refreshed quarterly) is run through Testing Center on every topic addition or instruction change. Target: ≥95% correct topic routing on the corpus; any misroute is a defect to fix, not noise to accept.
- The fallback/intake topic exists precisely so that "confidently wrong topic" never happens — ambiguous utterances route to structured intake, not to a guess.
- **[NEW] The fallback topic's description is written last and deliberately broad.** It is the one topic where "mutually exclusive by design" is intentionally inverted; it must be re-reviewed every time a new topic is added so it keeps catching what the specific topics don't claim.
- **[NEW] The corpus is scrubbed before it enters source control.** Real case subjects carry names, emails, and account details; committing them replicates personal data into git history permanently. A scrubbing pass (replace real identifiers with realistic synthetic ones, preserving the linguistic shape that drives routing) is mandatory before any utterance is committed, and the DPO review in §3 applies to the corpus itself, not just to topics that read personal data.

## 3. Action safety

- Reads are unrestricted; **every write action is confirmation-gated**, and anything sensitive (provisioning, ownership changes, team membership) sits behind a human approval step.
- No action ever touches authentication, credentials, or SSO configuration.
- All action Apex/flows are bulkified and, where processing is heavy, asynchronous — designed for the reasoning engine's multi-call looping, not a single invocation.
- Agent runs under least-privilege permissions: it can see and do only what its topics require. DPO review is part of the definition-of-done for any topic that reads personal data.
- **[NEW] Kill switch, at two levels, no deploy required.** (a) The whole agent can be deactivated from Setup in minutes. (b) Each topic's action flows check the org-standard `Application_Settings__c` bypass pattern, so a misbehaving topic can be neutered by flipping a setting while the agent stays up. Rollback-without-deploy is part of the definition-of-done, consistent with every other automation standard in this org (Contact Role V5, Customer Journey).

## 4. Measurement — the agent is an experiment with a control

- **Baseline first.** Before each topic ships, record its cluster's trailing-12-month case volume (we have this). The topic's success metric is deflection against that baseline, not anecdote.
- Per-topic KPIs, reviewed monthly:
  - **Deflection rate** — conversations resolved with no case created.
  - **Escalation quality** — % of agent-created cases arriving complete (ID, attempted action, error, business reason) vs. needing a follow-up question from the team.
  - **Grounding failures** — any confirmed invented-fact incident (target: zero; every incident is a post-mortem).
  - **Routing accuracy** on the live corpus.
  - **Credit consumption per resolved conversation** — efficiency, not just capability.
- Case records created by the agent carry an origin marker so all of this is reportable in standard Salesforce reporting.
- **[NEW] "Resolved" is defined before the first KPI is read:** a conversation that ended with no case created *and* no repeat contact on the same subject within 7 days. Without the second clause, deflection over-counts users who gave up and emailed the team directly.

## 5. The iteration loop — where world-class actually lives

- **Weekly (first 8 weeks, then fortnightly):** review escalated conversations and misroutes. Every escalation is a signal: either the Knowledge has a gap (fix the article), the instructions have a gap (fix the topic), or the request genuinely needs a human (fine).
- Escalated-case themes feed the article backlog directly — the agent's failures write next month's Knowledge.
- **[CHANGED]** Agent metadata (topics, instructions, flows) lives in source control via the CLI pipeline; every change is versioned, sandbox-tested in KJDEV against the utterance corpus, then promoted per the **Promotion Runbook** (companion doc). No hand-editing in production. *Two carve-outs v1 missed:* (a) Knowledge article **content** promotes via the load script in §1, not the CLI — but from the same repo, same review gate; (b) flows arrive in LBR_PROD as **Draft** (org deploy setting) and are activated as an explicit runbook step — a topic is not "promoted" until its flows are verified Active.
- Quarterly: re-pull case volumes, compare against baseline, retire or merge underperforming topics, and re-prioritise the roadmap on data.

## 6. Surface & reachability

- The agent must be reachable where users actually are (Outlook/Teams world), and the Login/SSO topic specifically must be reachable **outside** Salesforce authentication.
- **[NEW]** An unauthenticated channel means the Login/SSO topic's grounded Knowledge is effectively **public**. Its articles are authored to that exposure: no internal system names, no security-relevant configuration detail, no personal data — guidance and escalation paths only. Every article attached to an unauthenticated topic gets an explicit "safe for public" check in review.
- Proactive outreach (flow-triggered nudges) is templated and deterministic by default; agent-composed outreach only where personalisation demonstrably earns its credit cost.
- **[CHANGED]** Frequency caps on proactive nudges — notification fatigue kills adoption faster than any capability gap. *The cap is enforced by a named mechanism:* a last-nudged timestamp (or counter) field checked by the sending flow, not by convention. Which field, on which object, is specified in each nudge's design before it ships.

## 7. Definition of done — per topic

A topic ships when all of the following are true:

1. Grounding article(s) verified against retrieved metadata; no placeholders. **[CHANGED]** Article source files in the repo; loaded to Knowledge via the load script in both orgs.
2. Classification description checked for overlap against all existing topics; **[NEW]** fallback topic description re-reviewed against the new topic.
3. Actions built, bulkified, confirmation-gated where they write; DPO check done if personal data involved; **[NEW]** action flows honour the `Application_Settings__c` kill switch.
4. Utterance test set (min. 15 real utterances + 3 invention-bait traps) passing in Testing Center at ≥95% routing and 100% grounding fidelity. **[NEW]** Corpus entries scrubbed of personal data before commit.
5. **[NEW]** Test data for the topic's action paths seeded in KJDEV (the sandbox holds no production data — routing tests run dry, but action tests need records; seeding scripts live in the repo alongside the topic). Any external-service dependency (e.g. CPQ calculation service) verified authenticated in the sandbox before test sign-off.
6. Baseline volume recorded; KPI reporting in place; **[NEW]** "resolved" definition applied per §4.
7. Metadata in source control; deployed KJDEV → prod via CLI **per the Promotion Runbook, including flow activation verification**. **[CHANGED]**
8. Owner named for the topic's Knowledge and its monthly KPI review.
9. **[NEW]** Kill-switch behaviour tested: setting flipped in KJDEV, topic's actions confirmed inert, setting restored.
