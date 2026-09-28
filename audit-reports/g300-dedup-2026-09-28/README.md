# G300 duplicate sweep - re-run 28 Sep 2026

Re-run of `scripts/g300-dedup/g300_dedup_sweep.py` against Production,
read-only, with the 111 former names now in `g300_aliases.csv` (79 added
from the 26 Sep recall check). All data was fetched fresh; nothing was
reused from the 26 Sep run. Compare with `../g300-dedup-2026-09-26/`.
Nothing was changed in Salesforce.

## Files

| File | What it is |
|---|---|
| `g300_duplicate_candidates.csv` | Raw script output: 518 candidate pairs with signals, tier and triage evidence |
| `g300_candidates_with_prior_verdicts.csv` | The same rows plus `verdict_26sep` / `verdict_source`: the 26 Sep verdict where the pair was already verified, else `new - not verified` |
| `g300_completeness_gaps.csv` | Data problems on the G300 records themselves |
| `g300_sweep_summary.txt` | The script's run summary |

## What changed since 26 Sep

| | 26 Sep | 28 Sep |
|---|---|---|
| G300 Firm records | 302 | 303 |
| Candidate pairs | 376 | 518 |
| Tier 1 / 2 / 3 | 186 / 151 / 39 | 288 / 193 / 37 |
| Pairs within the G300 set | 1 | 2 |
| G300 records with a data gap | 159 | 156 |

- **Carried over:** 375 of the 376 verified pairs are still candidates,
  and they keep their 26 Sep verdict. 184 of the 185 confirmed
  duplicates are still in Salesforce.
- **New, not yet verified: 138 pairs.** 137 come from the new former
  names (96 tier 1, 42 tier 2). They are mostly older records carrying a
  firm's former name: 59 from the 2021 initial load, 56 from the
  Nov 2025 migration, and 2 from the 2026 bulk loads. Dentons gains the
  most. The other new pair is a Firm record created on 28 Sep (below).
- **Recall-check misses:** the sweep now catches 5 of the 38 records
  that the 26 Sep recall check found; those keep their recall-check
  verdict. The other 33 are typos (19), acronyms (3) and other forms
  (11) that name matching cannot catch.

## Record changes in Salesforce since 26 Sep

None of these went through the worklist; no row there has been approved.

- **Norton Rose Fulbright duplicate `001Px00000heXDiIAM` no longer
  exists.** It was a confirmed duplicate on 26 Sep (1 Office,
  2 contacts). It has been deleted or merged.
- **Akin Gump `001Px00000hloUDIAY` is now a second G300 record.** On
  26 Sep it was "AKIN GUMP STRAUSS HAUER & FELD LLP , DUBAI", classified
  as Akin Gump's Dubai office recorded as a Firm, to be re-parented as an
  Office. On 28 Sep at 10:23 UTC it was renamed to the firm's full name,
  given the firm's website and flagged G300 (last modified by Kieran
  Hansen). The within-G300 pass now pairs it with the original G300
  record `0016g00001ANnDBAA1`.
- **New duplicate created on 28 Sep:** "Jingtian & Gongcheng"
  `001Px00000ly6YwIAI` (11:07 UTC, Karnati Nihanth). It has the same name
  and website as G300 `0016g00001AOCqfAAH`.
- **`No_of_Offices__c` updated on 4 G300 records**, e.g. Hogan Lovells
  from 1 to 60, which matches its Office count.

## Next steps

- Verify the 138 new pairs the same way as on 26 Sep. They are mostly
  expected to be legacy former-name records rather than live duplicates.
- Settle the Akin Gump change before any merge involving either Akin
  Gump G300 record.
