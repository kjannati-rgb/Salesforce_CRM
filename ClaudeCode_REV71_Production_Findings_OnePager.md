# REV-71 — Production findings one-pager (for Cayla / sign-off meeting)

*Read-only analysis of LBR_PROD, 13 Jun 2026. 874 coded lines across 319 opportunities.*
*Nothing was changed in production — these are SELECT-only findings.*

## The headline: the historical codes are inconsistent manual entries, and the engine
## reproduces only **170 of 319 (53%)** of them. That split is the story.

The build is correct on the *consistent* mechanics. The *rules* the spec gave us don't
match what the business actually did on two specific patterns — and those need your ruling
before go-live and before any backfill.

## ✅ Confirmed — engine is built to match production reality
- **One code per deal:** 0 of 319 deals carry two different codes. Absolute.
- **Code goes on every line**, including the "other" anchor (Int'l lines under code 1 ×114; Law.com lines under code 3 ×74).
- **Active sellable bundles (Law.com Pro, Mid Market) are never coded** — 0 lines. They invoice on their own.
- **Bundle child lines are essentially never coded** — 2 of 874. Codes sit on standalone + bundle-parent lines.

## ⚠️ Decisions you need to make — each is a real rule the spec got wrong

**1. What makes a Law.com + International deal a "1" vs a "3"? It is NOT price.**
Of 113 deals with both Law.com and International present, **Law.com is the pricier line in
all 113** — International is never pricier. The spec's "highest-priced anchor wins" rule
would therefore code every one of them **1**. But the business coded **41 (38%) as 3**.
→ *Something other than line price decides Int'l vs Law.com. What is it? (lead product?
market/region? subscription type?) Until we know, the engine will mis-code ~38% of these.*

**2. Code 2 (GLL) appears on deals with no GLL product — 7 of 18 code-2 deals (39%).**
→ Is "GLL present → 2" the real rule, or does code 2 mean something broader? Likely some are
manual errors, but 39% is too high to dismiss.

**3. 102 deals carry a code the engine says shouldn't exist** — single-product deals, or
deals whose only products are Law.com-FAMILY add-ons (News Vault, Radar, Compass) with no
core Law.com/International/GLL line.
→ Should the "anchor" for code 1 be the **whole Law.com product family**, not just the LAWM
core SKU? That single change likely reconciles most of these 102.

**4. Original bundle questions** (children stamping, lone bundles, cross-family absorption) —
data says children/lone-bundles weren't coded historically; still your call for go-forward
policy on rare mixed deals. (See full decision list.)

## 💡 Backfill consequence (§7)
Because only 53% of historical codes reproduce, the existing codes **cannot be trusted as
the target**. The read-only audit (built, `scripts/rev71_backfill_audit.apex`) re-derives the
correct code and lists mismatches: **47 wrong-code, 102 should-be-blank, 22 partially-coded,
2 coded children.** Any remediation needs your rules locked AND Integra-owner confirmation
that changing a code mid-contract is safe (spec §8-Q6).

## What I recommend
- **Don't change the engine yet** — it correctly implements the consistent rules; changing it
  now would chase inconsistent history. Resolve #1–#3 with you first, then one contained
  flow update (the family-picking step) + re-test.
- **The engine can still go live for the clean majority** via the kill switches, with the
  Law.com+International subset (#1) held until the discriminator is known — if you want
  momentum before every question is closed.
