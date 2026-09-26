# G300 Firm Dedup Sweep

Read-only identification of duplicate/gap candidates in the 302 Account
records flagged `G300_Account__c = true` (RecordType = Firm).

## What it does

Runs these checks against the wider Firm-type Account population
(353k+ records) to find non-flagged accounts that look like duplicates
of a G300 firm, using signals that catch what a single check misses:

- **Pass 2 - Website domain match**: compares the normalized domain
  (scheme, `www.`, trailing slash, path and case ignored). Weak on its
  own: most duplicates have a blank Website, and many hits are people or
  unrelated organisations that carry the firm's domain.
- **Pass 3 - Normalized name match**: strips legal suffixes and
  descriptors (LLP, LLC, PC, Limited, mbB, Abogados, Law Firm, Et Al, ...),
  ignores case, accents, punctuation, `&`/`and` and spacing inside compound
  brands, then compares word by word. A candidate is reported when its
  core name
  - equals the G300 core (`name_exact`: "Dechert" / "Dechert LLP"),
  - extends it (`name_extends`: "Dechert Kazakhstan Limited"), or
  - is a short form of it (`name_short_form`: "Gibson Dunn",
    "Ogletree"; one-word short forms need 4+ letters).
  Former names from `g300_aliases.csv` are matched the same way
  (`alias_exact`, ...), so "McDermott Will & Emery" is found for
  McDermott Will & Schulte.
- **Pass 4 - Cross-identifier match**: LEI, BvD ID, Orbis ID, ALM
  Account ID, LinkedIn Company ID, Trade Register Number. In Production
  these are populated on Office records rather than Firm records, so this
  pass currently finds nothing; it is kept because it is cheap and exact.
- **Pass 5 - Completeness gaps**: flags G300 records themselves that
  are missing a Website or Segmentation, whose `No_of_Offices__c` is
  null/zero or disagrees with the real number of child Office records,
  and G300 flags sitting on non-Firm records.
- **Pass 6 - Within-G300 duplicates**: pairs of G300-flagged Firm
  records that match each other on the signals above (Passes 2-4 only
  look at non-G300 records).

Every candidate row also carries triage evidence for both records:
created date and creator, child Office count, and Contacts and
Opportunities across the record's Office hierarchy (in this org they sit
on Offices, not on the Firm).

## What it does NOT do

It does not merge anything. It does not decide which record survives.
Output is a candidate list for manual review - some hits will be
legacy predecessor-firm names (a firm that renamed or was absorbed
years ago) that are intentional historical records, not true
duplicates. Confirm merge direction per record before acting, in line
with the CE-master correction from the 24 Sep run. A merge must also
re-parent the duplicate's child Office records.

## Usage

```bash
sf org login web --alias <your-alias>   # if not already authenticated
python3 g300_dedup_sweep.py --target-org <your-alias>
```

Options: `--output-dir DIR` (default `./output`), `--aliases CSV`
(default `g300_aliases.csv` next to the script; `--aliases ''` to skip).

A failed or truncated query stops the run with exit code 2 instead of
being read as "no duplicates".

Outputs land in `./output/`:

- `g300_duplicate_candidates.csv` - one row per candidate pair with the
  signal(s) that flagged it and the triage evidence. **Sort on `tier`,
  not on signal count**: 1 = exact name/alias core, 2 = short form or
  extension, 3 = website/identifier only. Bulk-loaded duplicates have no
  website or identifiers, so they can only ever score one signal, while
  a person record carrying the firm's website scores two.
- `g300_completeness_gaps.csv` - G300 records with missing or stale data
- `g300_sweep_summary.txt` - run counts, per-tier and per-signal
  breakdown, and the creation batches the candidates came from

## Maintaining the alias list

`g300_aliases.csv` has one row per former name: `g300_id,alias,note`.
Add a row when a G300 firm merges or rebrands. Rows naming an Id that is
not a G300 Firm are reported and ignored.

## Tests

```bash
python3 -m unittest discover -s scripts/g300-dedup
```

The tests replace `sf_query` with a fake org, so they need no Salesforce
connection.
