# Smart Convert — UAT results (KJDEV)

**Date:** 2026-06-17 · **Org:** KJDEV sandbox · **Method:** end-to-end through the exact Apex the cockpit calls — `getMatch` (the preview the LWC renders) and `convert` / `createAndConvert` (what the buttons do) — with assertions on the resulting Lead/Account/Contact/Opportunity records. Nothing run against production.

## Result: 14/14 scenarios PASS · 40/40 automated tests PASS

### Preview behaviour (`getMatch` — what the rep sees before converting)
| # | Scenario | Asserted | Result |
|---|---|---|---|
| T1 | Renewal | brand GCR, active term ~+30d → motion **Renewal**, banner `ok` 🔄, existing customer, tier ONECLICK | ✅ |
| T2 | Upsell | Lexology Panoramic, active term ~+200d → motion **Upsell**, existing customer | ✅ |
| T3 | Cross-sell (family) | GAR (no GAR sub, holds GCR sibling) → motion **Cross-sell**, family **Specialist Platforms**, familyCustomer=true | ✅ |
| T4 | Cross-office detection | email matches a contact at Dentons **US**, lead in London → contact found, recommended office (UK) ≠ contact office (US) | ✅ |
| T5 | Guided create | no firm match → hasFirm=false, motion **New Business**, tier GUIDED_CREATE, dedup checks present | ✅ |
| T6 | Free-mail | `@gmail.com` → must NOT resolve a firm by domain → hasFirm=false | ✅ |
| T7 | Office ranking | UK lead → **Dentons UK** ranks first of 2 offices | ✅ |

### Convert behaviour (the buttons — records actually created/updated)
| # | Scenario | Asserted | Result |
|---|---|---|---|
| T8 | Renewal convert | opp **Type=Renewal**, name `Dentons - GCR - Renewal`, **CloseDate = term end (2026-07-15)**, GBP, landed in existing office, New_Account_Created=false, override=false, source='Smart Convert' | ✅ |
| T9 | **Cross-office link** | lands in the **contact's own (US) office**, links the **existing** contact, contact **not reparented** (still US), override flag clean, no opp | ✅ |
| T10 | Guided create convert | builds new **Firm** + office, opp **Type=New Business** (`… - New Business`), New_Account_Created=true, create reason stamped | ✅ |
| T11 | Disqualify | still **converts** (account + contact set), **no opportunity**, Disqualify_Reason stamped, Disqualified_At_Convert=true — single customer view preserved | ✅ |
| T12 | Telemetry / decision capture | rep override (chose US over recommended UK) → Overrode_Recommendation=true, Manual_Search_Used=true, Recommended_Office captured, opp currency **EUR**, confidence REVIEW | ✅ |
| T13 | Upsell convert | opp **Type=Upsell**, name `Dentons - Lexology Panoramic - Upsell` | ✅ |
| T14 | Cross-sell convert | opp **Type=Repeat Business**, name `Dentons - GAR - Cross-sell` | ✅ |

### Automated regression suite
`SmartConvertController_Test, BrandCustomerStatus_Test, SalesMotionService_Test, LeadMatchSelectService_Test, MatchDomainBackfill_Test, LeadConvertInvocable_Test` → **40 tests, 100% pass, 0 fail.**

## Coverage notes
- Every sales motion exercised both at **preview** and **convert** (the two doors share `SalesMotionService`, so they agree by construction).
- The two highest-risk behaviours are explicitly proven: the **cross-office no-reparent** link (T9) and the **disqualify-still-converts** SCV path (T11).
- Not covered here (environment limits): the live **LWC rendering** (needs a browser — server outputs verified instead), the **Pardot door** (no Pardot integration in KJDEV), and **open-brand-opp duplicate-warning** banner (needs a seeded open opp with a brand line item).
- Converting consumes a lead; the UAT leads created here are now converted test artifacts. Fresh scenario leads can be re-provisioned on request.

## Verdict
The Smart Convert engine behaves correctly across all tested scenarios in KJDEV. Remaining gates are **operational, not functional**: the prod match-key backfill (go-live gate), the analytics report-type Setup touch, and a browser pass over the LWC UI.
