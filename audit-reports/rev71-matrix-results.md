# REV-71 §6 Matrix Results — KJDEV, 2026-06-12

**Verdict: 22 / 22 scenarios pass.** Engine: `Quote_ALM_Code_Stamp` (Layer 1, hooked into
`Quote_AfterSave_MasterFlow`) + `Opp_ALM_Code_AfterSave` (Layer 2). Harness:
`scripts/rev71_run_matrix.sh` (builder / calc / mutate Apex templates). All scenario data
is tagged `ZZ REV71-M*`; teardown script staged, not yet run.

| # | Result | Quote lines | OLIs | Scenario |
|---|---|---|---|---|
| 1 | PASS | LAWM=null | LAWM=null | Single product — field untouched (monetary protection) |
| 2 | PASS | Law.com Pro=null (+children null) | — | Lone bundle — untouched |
| 3 | PASS | LAWM=1 LNVM=1 | LAWM=1 LNVM=1 | LAWM+LNVM → 1 |
| 4 | PASS | 4 lines all =1 | 4 OLIs all =1 | Two-year (MDQ-style) deal → all 1 |
| 5 | PASS | GLBM=2 LAWM=2 | GLBM=2 LAWM=2 | GLL decisive over LAWM |
| 6 | PASS | GLBM=2 LWKM=2 | GLBM=2 LWKM=2 | GLL decisive over LWKM |
| 7 | PASS | LAWM=1 LWKM=1 | LAWM=1 LWKM=1 | VAR: LAWM pricier → 1 |
| 8 | PASS | LAWM=3 LWKM=3 | LAWM=3 LWKM=3 | VAR: LWKM pricier → 3 |
| 9 | PASS | LWKM=3 TALM=3 | LWKM=3 TALM=3 | LWKM+TALM → 3 |
| 10 | PASS | LAWM=1 LNVM=1 TALM=1 | same | Line added → all re-stamped |
| 11 | PASS | LAWM=null | LAWM=null | Line deleted, drops to 1 product → code cleared |
| 12 | PASS | LAWM=3 LWKM=3 | LAWM=3 LWKM=3 | Repriced → code flips 1→3 on all lines |
| 13 | PASS¹ | LNVM=null NYLM=null | same | No anchor → no code; Flow_Log visibility rows written by BOTH layers |
| 14 | PASS¹ | Law.com Pro=null LNVM=null | LNVM=null | Bundle+standalone, no anchor (spec §8-Q4 assumption documented) |
| 15 | PASS | 200/200 lines =1 across 10 quotes | n/a (non-primary) | Bulk load: no recursion, no row locks, correct codes |
| 16 | PASS² | n/a (no quote) | children(ParentID)=null; Law.com Pro=1 LAWM=1 TALM=1 | Legacy-bundle children excluded; standalone stamped |
| 17 | PASS³ | LAWM=1 LNVM=1 | same | QLE-equivalent add+save (CPQ Quote API read→calculate→save) |
| 18 | PASS | LAWM=1 LNVM=1 | OLIs created already carrying 1 | Primary set AFTER stamping → twin-field creation-sync carries codes |
| 19 | PASS³ | LAWM=1 LNVM=1 | same | Renewal-type quote stamped with zero user action |
| 20 | PASS³ | LAWM=3 LWKM=3 | same | Amendment-type quote, mix change → recalculated |
| 21 | PASS | n/a | LAWM=1 LNVM=1 | Manual OLIs, no quote → Layer 2 stamps |
| 22 | PASS | n/a | values stable, no churn | Same-value re-save → no writes, no recursion |

## Footnotes / caveats

1. **13–14:** the harness's automated verdict said FAIL because its Flow_Log delta counter hit
   an sf CLI quirk (CSV mode renders aggregate COUNT values as an empty row). Manually
   verified: field outcomes correct AND six `%no anchor%` Flow_Log rows written during the
   two scenarios (Layer 1 on quotes Q-211443/Q-211444, Layer 2 on the M13 opportunity).
   Counter fixed in the harness (JSON parse) for future runs.
2. **16:** a true inactive-product OLI (`Law.com Premium Bundle`) cannot be INSERTED via API —
   no active PricebookEntry exists for an inactive product. That state exists only as
   pre-existing production data; the §7 backfill audit covers it. The child-exclusion logic
   under test is product-agnostic (`SBQQ__ParentID__c`), exercised here with an active parent.
3. **17, 19, 20:** mechanism-equivalent approximations. 17 uses the CPQ Quote API (same code
   path as a QLE save). 19/20 use quotes of `SBQQ__Type__c` Renewal/Amendment built directly
   rather than CPQ contract-driven generation (needs a contracted-order pipeline KJDEV's empty
   data can't host). Recommend demonstrating genuine renewal/amendment generation on a
   contracted test account during stakeholder demo.

## Observations for hardening (non-blocking)

- The no-anchor visibility log writes one row per evaluation (initial save + async calc
  update), so 2–3 rows per no-anchor quote save. Consider a "log only on first detection /
  on change" refinement before production to keep Flow_Log tidy.
- Throughout the run the engine's idempotency held: repeated evaluations of unchanged quotes
  produced zero writes (scenario 22 explicitly; implicitly on every async re-fire).
