# REV-71 — final coding rule (RESOLVED by Brady Blevins, ALM Sales Ops, 14 Aug 2025)

Supersedes the earlier "clean hierarchy" reading and the `…_Brady_Confirmation_Email` draft.

## The confirmed rule
The Total Contract Value code is set by the **PRIMARY product of the bundle = the one with the MOST REVENUE**:

| Condition | TCV code | Bundle |
|---|---|---|
| GLBM present | **2** | Global Leaders in Law (GLBM is always the primary) |
| LAWM + LWKM both present, **LAWM has more revenue** | **1** | Law.com Premium (Law.com is primary) |
| LAWM + LWKM both present, **LWKM has more revenue** | **3** | Law.com International (International is primary) |
| LAWM only (no LWKM) | **1** | Premium |
| LWKM only (no LAWM) | **3** | International |
| 2+ standalone, no anchor | *(no code)* | — |
| Single product / lone real bundle | *(no code)* | **CONFIRMED correct (Cayla, 18 Jun 2026)** — even a standalone Law.com International gets no code; one line has nothing to consolidate |

Brady's words: *"Law.com is the primary product for it to be TCV 1 (i.e. the most revenue)… Same products
but International is the primary product (most revenue) — could be coded TCV 3."* And the correction:
**a Premium bundle (1) CAN contain Law.com International** — it just isn't the primary there.

## What this confirmed / changed
- **Confirmed:** the discriminator is revenue (primary = most revenue) — exactly the original VAR rule.
- **Corrected my detour:** I'd briefly read his first email as "International present → always 3" and
  built a clean hierarchy; that was wrong. Reverted to the revenue rule. Engine 11/11 green.
- **Princeton deal is CORRECT, not a mis-coding:** Law.com £10k > International £5k → Law.com primary → code 1. ✓
- Law.com Pro / Mid Market Pro remain non-TCV-coded (Dispatch Code / Promo-'Z'). GLBM decisive for 2.

## Engine status
`Quote_ALM_Code_Stamp` + `Opp_ALM_Code_AfterSave` use the revenue rule (highest-revenue anchor among
LAWM/LWKM; GLBM→2). `Use_Net_Total_Price` CMDT toggle is live again (chooses net vs list basis).
**Tie-break: exactly-equal LAWM vs LWKM revenue → code 1 (Law.com Premium) — CONFIRMED by Brady, 14 Aug 2025.**
The engine already implements this (the VAR formula uses `vFam1Total >= vFam3Total`, so a tie resolves to 1).
KJDEV: REV71_ALMCodeFlow_Test 11/11 green.

## Backfill (§7) — the REAL clean-up, by the revenue rule
Read-only audit of production (`scripts/rev71_backfill_audit.apex`): **320 coded opps — 171 match,
47 wrong code, 102 should be blank.** Full list: `audit-reports/REV71_backfill_mismatches_revenue_rule.csv`.
- **47 WRONG_CODE** — stored code ≠ revenue-derived (mostly deals coded 3 where Law.com actually has more
  revenue → should be 1; plus "coded 2 with no GLL"). e.g. one deal LAWM £128,345 vs LWKM £35,500 coded 3.
- **102 SHOULD_BE_BLANK** — single-product / no-anchor deals carrying a code that the rule wouldn't set.
- Remediate only with explicit approval + Integra confirmation that retro code changes are safe (spec §8-Q6).

## Remaining
- ~~Open a tie-break note to Brady~~ **CLOSED 15 Jun 2026 — Brady confirmed exact-equal revenue → code 1.**
  Engine already implements this; no change needed.
- ~~Rewrite the REV-71 ticket description~~ **DONE** — description now carries this bundle-family/revenue model.
- REV-71 is **rule-complete, every edge case confirmed, engine-green** — ready for the demo → §10 sign-off → prod deploy.
  No remaining rule questions.
