# REV-71 — Deal combinations: decisions needed (for Cayla)

Context: the automation stamps the Integra consolidation code (1 = Law.com Premium family,
2 = GLL family, 3 = Law.com International family) onto opportunity product lines. Integra
receives an Excel of the line items and merges rows **with the same code** into one invoice
line. It cannot see Salesforce's bundle structure (parent/child) — the code is the only
grouping signal. One key fact drives several questions below: **in a real CPQ bundle, the
money usually sits on the child lines, not the bundle header.**

## Production evidence (read-only query of LBR_PROD, 13 Jun 2026)

874 coded lines across **319 opportunities**. Distribution: 633×code 1, 57×code 2, 184×code 3.

**What the live data CONFIRMS (the engine is built to match these):**
- **One code per deal: 0 of 319 deals carry two different codes.** Rock solid.
- **The code goes on every line regardless of product** — Law.com International (LWKM) lines
  appear under code 1 (114×) and Law.com (LAWM) lines appear under code 3 (74×). So the
  "losing" anchor's lines DO take the winning family's code. The engine does exactly this.
- **Active real bundles never get a code** — Law.com Pro and Mid Market Pro Bundle: 0 coded
  lines, ever. Strong support that a standalone-sellable bundle invoices on its own and is
  NOT given a consolidation code (informs Q2/Q3).
- **Bundle children are essentially never coded** — only 2 of 874 coded lines are CPQ children
  (ParentID populated). Historically the code sits on standalone + bundle-PARENT lines. This
  actually supports the current "exclude children" build, not the "code every child" change.

**What the live data REVEALS as a problem (this reframes the backfill):**
- The production codes are the **manual, inconsistent history REV-71 exists to replace** — they
  validate the engine's *structure* but must NOT be treated as a clean oracle of "correct":
  - **7 of 18 code-2 deals (39%) contain NO GLL product** — directly at odds with the spec's
    "code 2 = GLL family / GLL-decisive" rule. Manual error or an unknown meaning — Cayla input needed.
  - Real examples found: LAWM+LWKM coded **2** with no GLL present; an LRLM add-on coded **1**
    alone; a deal with LAWM coded 3 while its LWKM sibling sits **blank** (partial coding).
  - ~5% of lines on coded deals are blank (manual misses).
- **Consequence for §7 backfill:** the audit must compare history against the engine's
  *derived-correct* code and treat mismatches as candidate CORRECTIONS — not assume the
  existing code is right. Expect a meaningful correction rate.

## Settled — built, tested, no discussion needed

| Combination | What happens |
|---|---|
| Single product (any number of years) | No code. Field keeps its monetary use — never touched. |
| 2+ standalone products, one anchor family present (e.g. Law.com + News Vault) | Every line gets the family code (1 or 3). |
| Any GLL product present on a multi-product deal | Code 2 on the deal, regardless of price ("GLL is decisive"). |
| Multi-year deals | Same code on every line of every year. |
| Line added / deleted / repriced | Codes recompute automatically on the next save; deal dropping to one product clears the code. |

## Needs a ruling — one row per question

| # | Combination (example) | What the automation does TODAY | Question for Cayla | Options |
|---|---|---|---|---|
| 1 | **GLL bundle + Law.com standalone** (same family logic, mixed structure) | Codes the bundle HEADER + the standalone with 2. Child lines (where the money sits) stay blank. | Since Integra groups by code and the value is on the child lines — must the children carry the 2 as well? | **A:** header + standalone only (current). **B (recommended):** every line of the deal, children included — one rule, value rows always grouped. |
| 2 | **Lone bundle, nothing else** (just Law.com Pro) | No code at all. | How does Integra merge a solo bundle's lines into one invoice line today — does its own product mapping handle it, or were these deals being hand-coded too? | **A:** leave uncoded (current — matches the fact that most historical lines carry no code). **B:** lone bundles also need a code → much bigger coding population, new code semantics. |
| 3 | **A real bundle + a standalone anchor from a DIFFERENT family** (Law.com Pro bundle + Law.com International standalone) | The bundle header gets code 3 → the whole Pro bundle would merge into the International invoice line. | Is absorbing a real bundle into another family's invoice line ever right? Or should real bundles always invoice on their own line? | **A:** bundle absorbed (current logic). **B:** real bundles never coded; only true standalones group — but then a lone anchor standalone has nothing to pair with → no code at all on this deal. |
| 4 | **A real bundle + a NON-anchor standalone** (Law.com Pro + News Vault) — spec §8-Q4 | No code anywhere; deal is logged for human review. | Correct? The standalone invoices separately from the bundle. If they must merge, which code would even apply (Pro isn't one of the three families)? | **A:** leave separate + review log (current, per spec working assumption). **B:** define a new rule. |
| 5 | **Two real bundles on one deal** (GLL bundle + Law.com Pro bundle) | GLL is decisive → BOTH bundle headers get 2 → the Pro bundle merges into the GLL invoice line. | Same shape as #3: should one real bundle ever absorb another? | **A:** current behaviour. **B:** each real bundle invoices separately; codes only group standalones. |
| 6 | **2+ standalones, NO anchor anywhere** (News Vault + NYLJ) — spec §8-Q2 | No code; logged for review. Lines invoice separately. | Confirm finance is happy these stay as separate invoice lines (or that someone actions the review log). | **A:** stay separate + log (current). **B:** manual code by ops on flagged deals. |
| 7 | **Law.com AND International both on one deal, equal value** | Pricier family wins; an exact tie goes to Law.com (code 1). | Confirm the tie-break (spec is silent; assumption is documented in the flow). | **A:** tie → 1 (current). **B:** tie → 3, or flag for review. |
| 8 | **Already-invoiced open deals (backfill)** — spec §8-Q6 | Nothing retroactive: existing open deals only re-code when next edited. A read-only audit will list mismatches before any mass fix. | If Integra already consumed an earlier code on a mid-contract deal, is changing it later safe? | Needed before approving any backfill remediation. |

## Why "code on every line" (option B in #1) is the engineering recommendation

ParentID can't substitute: it's blank on standalones and virtual bundles (the main case),
blank on the bundle header itself (it's a child→parent pointer, not a group key), absent on
manual/legacy lines, and invisible to Integra anyway. The code is already the working
contract — ~872 production lines prove finance reads it. One mechanism, one rule:
**same code = same invoice line**, on every row that belongs to the group.

## What changes per answer (engineering impact)

- #1 option B, #3/#5 either way: contained change to the stamping step in both flows
  (the family-picking logic is untouched) + test updates. ~Half a day including re-verification.
- #2 option B would be a bigger redesign (new trigger conditions for solo-bundle deals) —
  worth knowing before the demo.
- #6/#7 are confirmations of already-built behaviour; #8 gates the backfill only.
