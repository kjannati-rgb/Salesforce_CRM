# REV-71 — Demo Walkthrough (ALM Invoice Consolidation Code Automation)

**For:** Cayla + ALM invoicing stakeholders · **Env:** KJDEV sandbox · **Prepared:** 15 Jun 2026
**Goal of the session:** show the engine works against the agreed rules → get business sign-off to deploy to production.

---

## 1. What this does, in one breath
When a multi-product ALM deal is sold, Integra needs **one consolidated invoice line**, and which line it consolidates onto is driven by a **Total Contract Value code (1 / 2 / 3)** on every product line. Today that code is **typed in by hand** — which is why the production history is inconsistent (e.g. ~39% of "code 2" deals have no Global Leaders product on them at all). REV-71 **derives the code automatically and identically on every line of the deal**, the moment the deal is priced or edited, so Integra always consolidates correctly and no one has to remember the rule.

## 2. The rule, on one slide
The code = the **primary product of the bundle = the one with the most revenue**:

| If the deal contains… | Code | Why |
|---|---|---|
| **Global Leaders (GLBM)** — anywhere | **2** | GLBM is always the primary |
| **Law.com + International**, Law.com has more revenue | **1** | Law.com Premium bundle |
| **Law.com + International**, International has more revenue | **3** | Law.com International bundle |
| **Equal revenue** (exact tie) | **1** | Premium wins the tie — *confirmed by Brady, 15 Jun 2026* |
| Law.com only / International only | **1 / 3** | Single anchor takes its own code |
| Multi-product but **no anchor** | *(blank)* | We don't guess — left blank + logged for review |
| Single product / lone bundle | *(blank)* | Nothing to consolidate |

> Law.com Pro and Mid-Market are **not** TCV-coded (they use Dispatch / Promo codes) — the engine leaves them alone.

---

## 3. The 5-minute live demo (golden path)
Open each deal in KJDEV and point at the **TCV code on the product lines**. The story builds in six beats. Links open the record directly.

### Beat 1 — the core rule, and its mirror image
> *"Same two products. The only thing that changes is which one is bigger."*

| # | Deal | What's on it | Code | Say this |
|---|---|---|---|---|
| 1 | [M07 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000osq4tIAA) | Law.com **8,000** · International 4,000 | **1** | "Law.com is the bigger number, so it's a Premium bundle → **1**." |
| 2 | [M08 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000oslGWIAY) | Law.com 4,000 · International **8,000** | **3** | "Exact same products — but now International is bigger → **3**. Nothing else changed." |

That pair *is* the whole revenue rule. Everything else is a refinement.

### Beat 2 — the tie-break you just confirmed
| # | Deal | What's on it | Code | Say this |
|---|---|---|---|---|
| 3 | [SMOKE-TIE →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000owGikIAE) | Law.com **5,000** · International **5,000** | **1** | "Exactly equal — the edge case Brady signed off on the 15th. Premium wins the tie → **1**." |

*(This deal was built live during testing on 15 Jun — it's the proof the confirmed tie-break is actually running, not just written down.)*

### Beat 3 — the override
| # | Deal | What's on it | Code | Say this |
|---|---|---|---|---|
| 4 | [M05 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000osfuEIAQ) | **Global Leaders** 10,000 · Law.com 5,000 | **2** | "Whenever Global Leaders is on the deal, it's always **2** — revenue doesn't even get a vote." |

### Beat 4 — the guardrails (what it deliberately does *not* do)
> *"Just as important as stamping the right code is not stamping the wrong one."*

| # | Deal | What's on it | Code | Say this |
|---|---|---|---|---|
| 5 | [M01 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000osjbHIAQ) | Single product | *(blank)* | "One product — nothing to consolidate, so we leave it alone." |
| 6 | [M13 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000osoawIAA) | Two add-ons, **no anchor** | *(blank)* | "Multi-product, but no Law.com / International / Global Leaders to anchor on. We **don't guess** — we leave it blank and log it for a human to check." |

### Beat 5 — it's live, not a one-time stamp
| # | Deal | What's on it | Code | Say this |
|---|---|---|---|---|
| 7 | [M12 →](https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com/006Ae00000ossppIAA) | International **9,000** · Law.com 3,000 (re-priced) | **3** | "This one started as a Premium deal. We re-priced it so International became the bigger line — and the code **re-derived itself** to 3 automatically. Change the deal, the code keeps up." |

### Beat 6 — the point of all of it
Open **any** deal above and show that **every product line carries the same code**. *"That's what lets Integra roll the whole deal onto one invoice line. One deal, one code, every line — automatically."*

---

## 4. Questions you'll likely get — and the answers
- **"What about the deals already coded by hand?"** Go-live changes nothing historical — the engine only fires when a deal is priced or edited. Cleaning up the back-catalogue (we found 47 mis-coded + 102 that shouldn't carry a code) is a **separate, deliberate** exercise that needs Integra's OK that re-coding old deals is safe to re-invoice.
- **"Can we turn it off if something goes wrong?"** Yes — a single org switch (`Disable_Autolaunch_Lightning_Flow__c`) is the kill switch; no redeploy needed.
- **"How do we know it's reliable?"** 22-scenario test matrix + a 10-method automated regression suite, **all green**, re-verified live in dev today. No-anchor cases are logged, not silently dropped.
- **"Does it touch Law.com Pro / Mid-Market?"** No — those use different codes and the engine ignores them.
- **"What if a salesperson overrides it?"** *(Open question to confirm in the session — current build re-derives on every edit; if manual overrides should stick, that's a small config change.)*

## 5. The ask
**Business sign-off (§10) to deploy REV-71 to production.** On your go, deployment follows the runbook (flows deploy inactive → activate → verify with the regression suite), with the kill switch in place from minute one. The historical backfill stays a separate decision, pending Integra.

---

### Appendix — full scenario reference (all 24 test deals)
Every deal below currently shows the correct code in KJDEV (re-verified 15 Jun). The seven above are the demo path; the rest cover bulk, renewals/amendments, manual lines, twin-sync, and edge cases.

| Deal | Shape | Code | Proves |
|---|---|---|---|
| M01 | single product | — | no over-stamping |
| M02 | lone bundle | — | nothing to consolidate |
| M03 | Law.com + add-on | 1 | basic Premium |
| M04 | 4 lines, 2-yr | 1 | all lines coded alike |
| M05 | GLBM + Law.com | 2 | GLBM decisive |
| M06 | GLBM + International | 2 | GLBM decisive |
| M07 | Law.com richer | 1 | revenue rule |
| M08 | International richer | 3 | revenue rule |
| M09 | International + add-on | 3 | International anchor |
| M10 | line added | 1 | re-stamps on add |
| M11 | line deleted → single | — | clears when no longer multi |
| M12 | re-priced | 3 | live re-derivation (1→3) |
| M13 | no anchor | — | blank + visibility log |
| M14 | bundle + standalone, no anchor | — | blank + log |
| M15 | 200 lines / 10 quotes | 1 | bulk-safe |
| M16 | standalones + bundle children | 1 / — | children excluded |
| M17 | quote add + save | 1 | quote-editor path |
| M18 | primary set after stamp | 1 | new lines born coded |
| M19 | renewal-type | 1 | renewals |
| M20 | amendment-type | 3 | amendments |
| M21 | manual lines, no quote | 1 | manual-entry path |
| M22 | same-value re-touch | 1 | no needless churn |
| SYNC | Law.com + add-on | 1 | Quote→Opportunity sync |
| SMOKE-TIE | exact tie | 1 | confirmed tie-break (live) |
