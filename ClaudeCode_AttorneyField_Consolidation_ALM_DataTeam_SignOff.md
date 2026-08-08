# Sign-off request — Account "Attorney Count" field consolidation

**To:** ALM / Law.com Data Team (current editors of *ALM # of Attorneys*: Cindy Leung, Kieran Hansen, Ashton Thompson, Cayla Vichot, Jessica Silveira, Khris Fenton, Shawn Harlan)
**From:** Salesforce / RevOps
**Date:** 2026-06-19
**Re:** Retiring **"ALM # of Attorneys"** in favour of **"Number of Attorneys"** on Account — two confirmations needed

---

## TL;DR
We're consolidating two duplicate attorney-count fields on Account into one. The keeper is **"Number of Attorneys"**; **"ALM # of Attorneys"** (the field your team maintains) will be retired. Your recent prod data refresh (2026-06-19) **already set the two fields identical** across all 17,927 populated accounts, so the earlier "which value wins?" question is **resolved — nothing to decide there.** We now need just **two confirmations** before the production cutover.

---

## Why this affects your team
| Field (label) | API name | Status |
|---|---|---|
| **ALM # of Attorneys** | `of_Attorneys__c` | the one your team's load populates today → **being retired** |
| **Number of Attorneys** | `Number_of_Attorneys__c` | the **survivor** (keeper) |

Reports, the ALM Industry Category logic, and quote documents are being pointed at the survivor. Nothing automated *inside Salesforce* writes "ALM # of Attorneys" — it comes from your team's data refresh, which is why your sign-off matters.

*(Note: `Total US Attorneys` and `Total Non-US Attorneys` are NOT affected.)*

---

## Current state (after your 2026-06-19 refresh)
- **17,927** accounts have an attorney value; **both fields are identical** on every one (0 conflicts, 0 one-sided gaps). ✅
- This means the value-migration step is a no-op — we just consolidate onto "Number of Attorneys" and retire the old field.

---

## What we need you to approve

### ☐ 1. Going forward, your load must populate "Number of Attorneys"
Your refresh currently writes **"ALM # of Attorneys"** (`of_Attorneys__c`), which is being retired. Please **repoint your data-refresh / load job to write "Number of Attorneys"** (`Number_of_Attorneys__c`) instead — or write **both** until the old field is deleted.

> **Please confirm:** ✅ your load will target "Number of Attorneys" going forward. *(Tip: load firm/office counts at the Firm / Ultimate Account level — that's what quote documents read.)*

### ☐ 2. Timing
"ALM # of Attorneys" will first go **read-only** (still visible) for a soak of **~2–4 weeks**, then be deleted.

> **Please confirm:** ✅ the soak window works, or propose a different one. *(During the soak, your next refresh must already be writing "Number of Attorneys" — see #1 — or counts will stop updating.)*

---

## Safeguards
- **No data loss in the consolidation:** the fields are already equal, and we take a full backup of all values before retiring anything.
- **Reversible:** even after deletion the field is recoverable for **15 days**.
- **Already proven:** the full process ran cleanly in two sandboxes, including a 14,064-record migration with zero errors.
- **Read-only soak:** during the soak you can still *see* the old field to spot-check before it's removed.

---

## Sign-off

| # | Decision | Approve? | Notes |
|---|---|---|---|
| 1 | Refresh/load job will write "Number of Attorneys" going forward | ☐ | |
| 2 | ~2–4 week read-only soak before deletion | ☐ | |

**Name / role:** ______________________   **Date:** __________

Reply with approvals (or questions) and we'll schedule the production change. Nothing runs in production until both are confirmed.
