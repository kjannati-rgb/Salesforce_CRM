# Sign-off request — Account "Attorney Count" field consolidation

**To:** ALM / Law.com Data Team (current editors of *ALM # of Attorneys*: Cindy Leung, Kieran Hansen, Ashton Thompson, Cayla Vichot, Jessica Silveira, Khris Fenton, Shawn Harlan)
**From:** Salesforce / RevOps
**Date:** 2026-06-19
**Re:** Retiring **"ALM # of Attorneys"** in favour of **"Number of Attorneys"** on Account — your approval needed before we touch production

---

## TL;DR
We're consolidating two duplicate attorney-count fields on Account into one. The keeper is **"Number of Attorneys"**; **"ALM # of Attorneys"** (the field your team maintains) will be retired. Because your team is the source of this data, we need **three confirmations** from you before we run anything in production. No production data has been changed yet — this has been built and tested in two sandboxes.

---

## Why this affects your team
There are two fields holding the same thing:

| Field (label) | API name | Status |
|---|---|---|
| **ALM # of Attorneys** | `of_Attorneys__c` | the one your team edits today → **being retired** |
| **Number of Attorneys** | `Number_of_Attorneys__c` | the **survivor** (keeper) |

Reports, the ALM Industry Category logic, and quote documents are being pointed at the survivor. We confirmed that **nothing automated writes "ALM # of Attorneys" — it's maintained manually by your team**, which is exactly why your sign-off matters.

*(Note: `Total US Attorneys` and `Total Non-US Attorneys` are NOT affected.)*

---

## What we need you to approve

### ☐ 1. How to resolve value conflicts (the main decision)
Across **29,684** accounts where "ALM # of Attorneys" has a value:
- **28,953** already match "Number of Attorneys" — no change.
- **109** have "Number of Attorneys" blank — we'll copy your ALM value in.
- **622** have **different** values in the two fields.

**Our proposal for the 622: your ALM value wins** — we overwrite "Number of Attorneys" with the "ALM # of Attorneys" figure. Rationale: your field is the actively-maintained ALM source of truth.

> **Please confirm:** ✅ "ALM value wins on conflicts" — OR tell us if any accounts/values should be handled differently. *We can send you the list of all 622 conflicting accounts (old vs new value) for review before you decide.*

### ☐ 2. Going forward, maintain "Number of Attorneys"
After cutover, please enter/maintain attorney counts in **"Number of Attorneys"** instead of "ALM # of Attorneys."

> **Please confirm:** ✅ your team will switch to "Number of Attorneys", **and** flag any data-load / import / spreadsheet / ETL routine that currently populates "ALM # of Attorneys" so we can repoint it. *(Tip: firm/office attorney counts should be loaded at the Firm / Ultimate Account level — that's what quote documents read.)*

### ☐ 3. Timing
"ALM # of Attorneys" will first go **read-only** (still visible) for a soak period of **~2–4 weeks**, then be deleted.

> **Please confirm:** ✅ the soak window works, or propose a different one.

---

## Safeguards (so you can approve with confidence)
- **No data loss:** every "ALM # of Attorneys" value is copied into "Number of Attorneys" before anything is retired; a full backup of all 29,684 values is taken first.
- **Reversible:** the value migration can be rolled back from the backup; even after deletion the field is recoverable for **15 days**.
- **Already proven:** the full process ran cleanly in two sandboxes, including a 14,064-record migration with zero errors.
- **Read-only soak:** during the soak you can still *see* the old field to spot-check before it's removed.

---

## Sign-off

| # | Decision | Approve? | Notes |
|---|---|---|---|
| 1 | ALM value wins on the 622 conflicts | ☐ | |
| 2 | Team maintains "Number of Attorneys" going forward (+ remap any load jobs) | ☐ | |
| 3 | ~2–4 week read-only soak before deletion | ☐ | |

**Name / role:** ______________________   **Date:** __________

Reply with approvals (or questions) and we'll schedule the production change. Nothing runs in production until all three are confirmed.
