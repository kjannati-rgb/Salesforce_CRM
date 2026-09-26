# G300 Firm Dedup Sweep

Read-only identification of duplicate/gap candidates in the 302 Account
records flagged `G300_Account__c = true` (RecordType = Firm).

## What it does

Runs four checks against the wider Firm-type Account population
(353k+ records) to find non-flagged accounts that look like duplicates
of a G300 firm, using signals that catch what a single check misses:

- **Pass 2 - Website exact match**: fast, but misses duplicates with a
  blank Website field (most of them, based on the manual spot-check).
- **Pass 3 - Normalized name match**: strips legal suffixes (LLP, LLC,
  PC, P.C., PLLC, etc.) and matches on the remaining core name. Catches
  the "Ballard Spahr" vs "Ballard Spahr LLP" pattern regardless of
  Website.
- **Pass 4 - Cross-identifier match**: LEI, BvD ID, Orbis ID, ALM
  Account ID, LinkedIn Company ID, Trade Register Number. Harder to
  fake a false match on than a name or domain string.
- **Pass 5 - Completeness gaps**: flags G300 records themselves that
  are missing a Website, Segmentation, or have zero/null Offices -
  "clean" isn't just "not duplicated."

## What it does NOT do

It does not merge anything. It does not decide which record survives.
Output is a candidate list for manual review - some hits will be
legacy predecessor-firm names (a firm that renamed or was absorbed
years ago) that are intentional historical records, not true
duplicates. Confirm merge direction per record before acting, in line
with the CE-master correction from the 24 Sep run.

## Usage

```bash
sf org login web --alias <your-alias>   # if not already authenticated
python3 g300_dedup_sweep.py --target-org <your-alias>
```

Outputs land in `./output/`:

- `g300_duplicate_candidates.csv` - candidate pairs, with the signal(s)
  that flagged each one (a row flagged by more than one pass is a
  stronger candidate)
- `g300_completeness_gaps.csv` - G300 records with missing data
- `g300_sweep_summary.txt` - run counts

## Manual spot-check that led to this script

A hand-run version of Pass 2 + Pass 3 against ~100 of the 302 firms
(via ad hoc SOQL) surfaced roughly 30 duplicate-candidate records,
almost all with a blank Website - including 3-4 duplicate copies each
of several major firms (Dechert, Fox Rothschild, DLA Piper, Debevoise
& Plimpton). Extrapolated across the full 302, expect on the order of
80-100 duplicate-candidate records once this script completes the
full sweep.
