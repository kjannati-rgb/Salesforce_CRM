---
title: Opportunity Stages — the stage model
owner: Kamyar Jannati (Head Data and CRM)
review-date: 2027-01-04
verified-against:
  - PROD retrieve 2026-07-04: objects/Opportunity (businessProcesses, recordTypes), standardValueSets/OpportunityStage, pathAssistants (Default_Opportunity, New_Business, Renewals, Cancellation)
  - PROD SOQL 2026-07-04: Opportunity grouped by StageName (599,130 records)
---

# Opportunity Stages — the stage model

Which stages an opportunity can use depends on its **record type**.

## New Business and Renewal opportunities

Both record types use the same stage list, in this order:

| Stage | Probability | Forecast category |
|---|---|---|
| Identify | 10% | Pipeline |
| Qualify | 20% | Pipeline |
| Evaluate | 50% | Best Case |
| Negotiate | 75% | Best Case |
| Contract Out | 90% | Most Likely |
| Closed Won – Pending Approval | 95% | Forecast |
| Closed Won | 100% | Closed (won) |
| Closed Lost | 0% | Omitted |

Notes:
- **You cannot set Closed Won yourself.** Sales users close deals by moving the opportunity to *Closed Won – Pending Approval* and submitting for approval; Finance approval moves it to Closed Won automatically. See the "Closing an opportunity" article.
- An opportunity can be set to Closed Lost from any open stage. Depending on your team, closed-lost reason fields are required — see the "Closing an opportunity" article.
- Probability is set automatically from the stage. "Forecast Pending" as a Forecast Status is restricted to specific teams (Lexology Pro, Specialist Platforms, Lexology Intelligence, Customer Experience, Lexology Academic).

## Cancellation opportunities

Cancellations have their own two-stage process:

| Stage | Probability | Notes |
|---|---|---|
| Cancellation - Pending Review | 95% | Entry stage; cancellation awaits Finance approval |
| Closed Won - Cancellation | 100% | Set automatically when the cancellation is approved — it cannot be set directly |

Both stages are omitted from forecasts.

## Read-only opportunities

The "Opportunity Readonly" record type shares the New Business stage list. These records are locked for editing; if you need one changed, raise a case.

## Stage guidance in the UI

Each record type has an active Path on the opportunity page showing the current stage and key fields per stage. The Path is the quickest way to see what a stage expects before you move to it.

## Stages you may see in old reports

"Evaluation" and "Close" are retired stage values. No opportunity currently holds them and they cannot be selected. If you see them referenced in an old report or list view filter, that filter matches nothing and should be updated.
